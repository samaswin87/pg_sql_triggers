# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Migrator::SafetyValidator do
  describe ".validate!" do
    context "when migration is safe" do
      let(:safe_migration) do
        Class.new(PgSqlTriggers::Migration) do
          def up
            execute "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
            execute "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
          end
        end.new
      end

      it "does not raise error for safe migration" do
        expect do
          described_class.validate!(safe_migration, direction: :up, allow_unsafe: false)
        end.not_to raise_error
      end

      it "does not raise error when allow_unsafe is true" do
        expect do
          described_class.validate!(safe_migration, direction: :up, allow_unsafe: true)
        end.not_to raise_error
      end

      it "handles down direction" do
        migration_down = Class.new(PgSqlTriggers::Migration) do
          def down
            execute "DROP TRIGGER IF EXISTS test_trigger ON users;"
            execute "DROP FUNCTION IF EXISTS test_func();"
          end
        end.new

        expect do
          described_class.validate!(migration_down, direction: :down, allow_unsafe: false)
        end.not_to raise_error
      end
    end

    context "when migration has unsafe DROP + CREATE pattern" do
      before do
        # Create a function in database to make it "existing"
        ActiveRecord::Base.connection.execute(
          "CREATE OR REPLACE FUNCTION unsafe_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
        )
      end

      after do
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS unsafe_func()")
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS unsafe_trigger ON users")
      rescue StandardError => _e
        # Ignore cleanup errors
      end

      let(:unsafe_migration) do
        Class.new(PgSqlTriggers::Migration) do
          def up
            execute "DROP FUNCTION unsafe_func();"
            execute "CREATE FUNCTION unsafe_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
          end
        end.new
      end

      it "raises UnsafeOperationError when unsafe pattern detected" do
        expect do
          described_class.validate!(unsafe_migration, direction: :up, allow_unsafe: false)
        end.to raise_error(described_class::UnsafeOperationError)
      end

      it "does not raise error when allow_unsafe is true" do
        expect do
          described_class.validate!(unsafe_migration, direction: :up, allow_unsafe: true)
        end.not_to raise_error
      end
    end

    context "when migration has unsafe DROP + CREATE pattern for trigger" do
      before do
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY)")
        ActiveRecord::Base.connection.execute(
          "CREATE OR REPLACE FUNCTION unsafe_trigger_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
        )
        ActiveRecord::Base.connection.execute(
          "CREATE TRIGGER unsafe_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION unsafe_trigger_func();"
        )
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS unsafe_trigger ON test_users")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS unsafe_trigger_func()")
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users")
      rescue StandardError => _e
        # Ignore cleanup errors
      end

      let(:unsafe_trigger_migration) do
        Class.new(PgSqlTriggers::Migration) do
          def up
            execute "DROP TRIGGER unsafe_trigger ON test_users;"
            execute "CREATE TRIGGER unsafe_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION unsafe_trigger_func();"
          end
        end.new
      end

      it "raises UnsafeOperationError when unsafe trigger pattern detected" do
        expect do
          described_class.validate!(unsafe_trigger_migration, direction: :up, allow_unsafe: false)
        end.to raise_error(described_class::UnsafeOperationError)
      end

      it "does not raise error when allow_unsafe is true" do
        expect do
          described_class.validate!(unsafe_trigger_migration, direction: :up, allow_unsafe: true)
        end.not_to raise_error
      end
    end

    context "when migration has triggers with same name on different tables" do
      before do
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY)")
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_posts (id SERIAL PRIMARY KEY)")
        ActiveRecord::Base.connection.execute(
          "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
        )
        ActiveRecord::Base.connection.execute(
          "CREATE TRIGGER same_name_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION test_func();"
        )
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS same_name_trigger ON test_users")
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS same_name_trigger ON test_posts")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_func()")
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users")
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_posts")
      rescue StandardError => _e
        # Ignore cleanup errors
      end

      let(:safe_trigger_different_table_migration) do
        Class.new(PgSqlTriggers::Migration) do
          def up
            # Dropping trigger on test_users, but creating on test_posts - should not match
            execute "DROP TRIGGER same_name_trigger ON test_users;"
            execute "CREATE TRIGGER same_name_trigger BEFORE INSERT ON test_posts FOR EACH ROW EXECUTE FUNCTION test_func();"
          end
        end.new
      end

      it "does not flag as unsafe when triggers have same name but different tables" do
        expect do
          described_class.validate!(safe_trigger_different_table_migration, direction: :up, allow_unsafe: false)
        end.not_to raise_error
      end
    end
  end

  describe ".detect_unsafe_patterns" do
    let(:migration) do
      Class.new(PgSqlTriggers::Migration) do
        def up
          execute "CREATE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
        end
      end.new
    end

    it "returns empty array for safe migrations" do
      violations = described_class.detect_unsafe_patterns(migration, :up)
      expect(violations).to eq([])
    end

    it "captures SQL from migration" do
      violations = described_class.detect_unsafe_patterns(migration, :up)
      # Should not have violations, but SQL should be captured
      expect(violations).to be_an(Array)
    end
  end

  describe ".parse_sql_operations" do
    it "parses DROP TRIGGER statements" do
      sql = ["DROP TRIGGER test_trigger ON users;"]
      operations = described_class.send(:parse_sql_operations, sql)
      expect(operations[:drops].count).to eq(1)
      expect(operations[:drops].first[:type]).to eq(:trigger)
      expect(operations[:drops].first[:name]).to eq("test_trigger")
      expect(operations[:drops].first[:table_name]).to eq("users")
    end

    it "parses DROP FUNCTION statements" do
      sql = ["DROP FUNCTION test_func();"]
      operations = described_class.send(:parse_sql_operations, sql)
      expect(operations[:drops].count).to eq(1)
      expect(operations[:drops].first[:type]).to eq(:function)
      expect(operations[:drops].first[:name]).to eq("test_func")
    end

    it "parses CREATE TRIGGER statements" do
      sql = ["CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"]
      operations = described_class.send(:parse_sql_operations, sql)
      expect(operations[:creates].count).to eq(1)
      expect(operations[:creates].first[:type]).to eq(:trigger)
      expect(operations[:creates].first[:name]).to eq("test_trigger")
      expect(operations[:creates].first[:table_name]).to eq("users")
    end

    it "parses CREATE FUNCTION statements" do
      sql = ["CREATE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"]
      operations = described_class.send(:parse_sql_operations, sql)
      expect(operations[:creates].count).to eq(1)
      expect(operations[:creates].first[:type]).to eq(:function)
      expect(operations[:creates].first[:name]).to eq("test_func")
    end

    it "parses CREATE OR REPLACE FUNCTION statements" do
      sql = ["CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"]
      operations = described_class.send(:parse_sql_operations, sql)
      expect(operations[:replaces].count).to eq(1)
      expect(operations[:replaces].first[:type]).to eq(:function)
      expect(operations[:replaces].first[:name]).to eq("test_func")
    end

    it "handles IF EXISTS in DROP statements" do
      sql = ["DROP TRIGGER IF EXISTS test_trigger ON users;"]
      operations = described_class.send(:parse_sql_operations, sql)
      expect(operations[:drops].count).to eq(1)
      expect(operations[:drops].first[:name]).to eq("test_trigger")
      expect(operations[:drops].first[:table_name]).to eq("users")
    end

    it "handles multiple operations" do
      sql = [
        "DROP FUNCTION test_func();",
        "CREATE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      ]
      operations = described_class.send(:parse_sql_operations, sql)
      expect(operations[:drops].count).to eq(1)
      expect(operations[:creates].count).to eq(2)
    end
  end

  describe ".parse_drop" do
    it "parses DROP TRIGGER with table" do
      sql = "DROP TRIGGER test_trigger ON users;"
      result = described_class.send(:parse_drop, sql)
      expect(result[:type]).to eq(:trigger)
      expect(result[:name]).to eq("test_trigger")
      expect(result[:table_name]).to eq("users")
    end

    it "parses DROP FUNCTION" do
      sql = "DROP FUNCTION test_func();"
      result = described_class.send(:parse_drop, sql)
      expect(result[:type]).to eq(:function)
      expect(result[:name]).to eq("test_func")
    end

    it "returns nil for non-DROP statements" do
      sql = "CREATE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = described_class.send(:parse_drop, sql)
      expect(result).to be_nil
    end
  end

  describe ".parse_create" do
    it "parses CREATE TRIGGER" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_create, sql)
      expect(result[:type]).to eq(:trigger)
      expect(result[:name]).to eq("test_trigger")
      expect(result[:table_name]).to eq("users")
    end

    it "parses CREATE FUNCTION with $$ body" do
      sql = "CREATE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = described_class.send(:parse_create, sql)
      expect(result[:type]).to eq(:function)
      expect(result[:name]).to eq("test_func")
      expect(result[:function_body]).to include("BEGIN RETURN NEW; END;")
    end

    it "parses CREATE FUNCTION with AS body" do
      sql = "CREATE FUNCTION test_func() RETURNS TRIGGER AS 'BEGIN RETURN NEW; END;' LANGUAGE plpgsql;"
      result = described_class.send(:parse_create, sql)
      expect(result[:type]).to eq(:function)
      expect(result[:name]).to eq("test_func")
    end

    it "returns nil for CREATE OR REPLACE" do
      sql = "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = described_class.send(:parse_create, sql)
      expect(result).to be_nil
    end
  end

  describe ".parse_replace" do
    it "parses CREATE OR REPLACE FUNCTION" do
      sql = "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = described_class.send(:parse_replace, sql)
      expect(result[:type]).to eq(:function)
      expect(result[:name]).to eq("test_func")
      expect(result[:function_body]).to include("BEGIN RETURN NEW; END;")
    end

    it "returns nil for CREATE TRIGGER" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_replace, sql)
      expect(result).to be_nil
    end
  end

  describe ".detect_drop_create_patterns" do
    before do
      # Create a function in database
      ActiveRecord::Base.connection.execute(
        "CREATE OR REPLACE FUNCTION existing_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      )
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute(
        "CREATE OR REPLACE FUNCTION existing_trigger_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      )
      ActiveRecord::Base.connection.execute(
        "CREATE TRIGGER existing_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION existing_trigger_func();"
      )
    end

    after do
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS existing_func()")
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS existing_trigger ON test_users")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS existing_trigger_func()")
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users")
    rescue StandardError => _e
      # Ignore cleanup errors
    end

    it "detects DROP + CREATE pattern for existing function" do
      operations = {
        drops: [{ type: :function, name: "existing_func", sql: "DROP FUNCTION existing_func();" }],
        creates: [{ type: :function, name: "existing_func", sql: "CREATE FUNCTION existing_func()..." }],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      expect(violations.count).to eq(1)
      expect(violations.first[:type]).to eq(:drop_create_pattern)
      expect(violations.first[:object_type]).to eq(:function)
      expect(violations.first[:object_name]).to eq("existing_func")
    end

    it "detects DROP + CREATE pattern for existing trigger with matching table_name" do
      operations = {
        drops: [{ type: :trigger, name: "existing_trigger", table_name: "test_users", sql: "DROP TRIGGER existing_trigger ON test_users;" }],
        creates: [{ type: :trigger, name: "existing_trigger", table_name: "test_users", sql: "CREATE TRIGGER existing_trigger..." }],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      expect(violations.count).to eq(1)
      expect(violations.first[:type]).to eq(:drop_create_pattern)
      expect(violations.first[:object_type]).to eq(:trigger)
      expect(violations.first[:object_name]).to eq("existing_trigger")
    end

    it "does not flag DROP + CREATE for trigger when table_name does not match" do
      operations = {
        drops: [{ type: :trigger, name: "existing_trigger", table_name: "test_users", sql: "DROP TRIGGER existing_trigger ON test_users;" }],
        creates: [{ type: :trigger, name: "existing_trigger", table_name: "other_table", sql: "CREATE TRIGGER existing_trigger..." }],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      # Should not match because table_name differs
      expect(violations).to be_empty
    end

    it "does not flag DROP + CREATE for non-existing function" do
      operations = {
        drops: [{ type: :function, name: "nonexistent_func", sql: "DROP FUNCTION nonexistent_func();" }],
        creates: [{ type: :function, name: "nonexistent_func", sql: "CREATE FUNCTION nonexistent_func()..." }],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      expect(violations).to be_empty
    end

    it "does not flag DROP + CREATE for non-existing trigger" do
      operations = {
        drops: [{ type: :trigger, name: "nonexistent_trigger", table_name: "test_users", sql: "DROP TRIGGER nonexistent_trigger ON test_users;" }],
        creates: [{ type: :trigger, name: "nonexistent_trigger", table_name: "test_users", sql: "CREATE TRIGGER nonexistent_trigger..." }],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      expect(violations).to be_empty
    end

    it "does not flag DROP + CREATE when types don't match" do
      operations = {
        drops: [{ type: :function, name: "test_func", sql: "DROP FUNCTION test_func();" }],
        creates: [{ type: :trigger, name: "test_func", sql: "CREATE TRIGGER test_func..." }],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      expect(violations).to be_empty
    end

    it "does not flag DROP + CREATE when names don't match" do
      operations = {
        drops: [{ type: :function, name: "func1", sql: "DROP FUNCTION func1();" }],
        creates: [{ type: :function, name: "func2", sql: "CREATE FUNCTION func2()..." }],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      expect(violations).to be_empty
    end

    it "detects multiple violations" do
      operations = {
        drops: [
          { type: :function, name: "existing_func", sql: "DROP FUNCTION existing_func();" },
          { type: :trigger, name: "existing_trigger", table_name: "test_users", sql: "DROP TRIGGER existing_trigger ON test_users;" }
        ],
        creates: [
          { type: :function, name: "existing_func", sql: "CREATE FUNCTION existing_func()..." },
          { type: :trigger, name: "existing_trigger", table_name: "test_users", sql: "CREATE TRIGGER existing_trigger..." }
        ],
        replaces: []
      }
      violations = described_class.send(:detect_drop_create_patterns, operations)
      expect(violations.count).to eq(2)
      # rubocop:disable Rails/Pluck
      object_types = violations.map { |v| v[:object_type] }
      # rubocop:enable Rails/Pluck
      expect(object_types).to contain_exactly(:function, :trigger)
    end
  end

  describe ".function_exists?" do
    before do
      ActiveRecord::Base.connection.execute(
        "CREATE OR REPLACE FUNCTION test_check_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      )
    end

    after do
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_check_func()")
    rescue StandardError => _e
      # Ignore cleanup errors
    end

    it "returns true for existing function" do
      expect(described_class.send(:function_exists?, "test_check_func")).to be true
    end

    it "returns false for non-existing function" do
      expect(described_class.send(:function_exists?, "nonexistent_func")).to be false
    end
  end

  describe ".trigger_exists?" do
    before do
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute(
        "CREATE OR REPLACE FUNCTION test_check_trigger_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      )
      ActiveRecord::Base.connection.execute(
        "CREATE TRIGGER test_check_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION test_check_trigger_func();"
      )
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_check_trigger ON test_users")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_check_trigger_func()")
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users")
    rescue StandardError => _e
      # Ignore cleanup errors
    end

    it "returns true for existing trigger" do
      expect(described_class.send(:trigger_exists?, "test_check_trigger")).to be true
    end

    it "returns false for non-existing trigger" do
      expect(described_class.send(:trigger_exists?, "nonexistent_trigger")).to be false
    end
  end

  describe ".build_error_message" do
    it "builds error message with violations" do
      violations = [
        {
          type: :drop_create_pattern,
          message: "Unsafe DROP + CREATE pattern detected",
          object_name: "test_func",
          object_type: :function
        }
      ]
      message = described_class.send(:build_error_message, violations, "TestMigration")
      expect(message).to include("UNSAFE MIGRATION DETECTED")
      expect(message).to include("TestMigration")
      expect(message).to include("Unsafe DROP + CREATE pattern detected")
      expect(message).to include("ALLOW_UNSAFE_MIGRATIONS=true")
    end
  end

  describe "UnsafeOperationError" do
    it "inherits from UnsafeMigrationError" do
      expect(described_class::UnsafeOperationError.superclass).to eq(PgSqlTriggers::UnsafeMigrationError)
    end

    it "stores violations" do
      violations = [{ message: "Test violation" }]
      error = described_class::UnsafeOperationError.new("Test message", violations)
      expect(error.violations).to eq(violations)
    end

    it "provides violation summary" do
      violations = [
        { message: "Violation 1" },
        { message: "Violation 2" }
      ]
      error = described_class::UnsafeOperationError.new("Test message", violations)
      summary = error.violation_summary
      expect(summary).to include("Violation 1")
      expect(summary).to include("Violation 2")
    end
  end
end
