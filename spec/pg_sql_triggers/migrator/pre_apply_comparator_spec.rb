# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Migrator::PreApplyComparator do
  describe ".compare" do
    let(:migration_instance) do
      Class.new(PgSqlTriggers::Migration) do
        def up
          execute "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
          execute "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
        end
      end.new
    end

    it "compares expected state with actual state" do
      result = described_class.compare(migration_instance, direction: :up)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:functions)
      expect(result).to have_key(:triggers)
    end

    it "handles down direction" do
      migration_down = Class.new(PgSqlTriggers::Migration) do
        def down
          execute "DROP TRIGGER IF EXISTS test_trigger ON users;"
          execute "DROP FUNCTION IF EXISTS test_func();"
        end
      end.new

      result = described_class.compare(migration_down, direction: :down)
      expect(result).to be_a(Hash)
    end
  end

  describe ".capture_sql" do
    let(:migration) do
      Class.new(PgSqlTriggers::Migration) do
        def up
          execute "SELECT 1"
          execute "SELECT 2"
        end
      end.new
    end

    it "captures SQL from migration" do
      captured = described_class.send(:capture_sql, migration, :up)
      expect(captured).to be_an(Array)
      expect(captured.count).to eq(2)
      expect(captured.first).to include("SELECT 1")
    end
  end

  describe ".parse_sql_to_state" do
    it "parses CREATE FUNCTION statements" do
      sql = ["CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"]
      state = described_class.send(:parse_sql_to_state, sql)
      expect(state[:functions].count).to eq(1)
      expect(state[:functions].first[:function_name]).to eq("test_func")
    end

    it "parses CREATE TRIGGER statements" do
      sql = ["CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"]
      state = described_class.send(:parse_sql_to_state, sql)
      expect(state[:triggers].count).to eq(1)
      expect(state[:triggers].first[:trigger_name]).to eq("test_trigger")
      expect(state[:triggers].first[:table_name]).to eq("users")
    end

    it "parses DROP statements" do
      sql = ["DROP TRIGGER test_trigger ON users;"]
      state = described_class.send(:parse_sql_to_state, sql)
      expect(state[:drops].count).to eq(1)
      expect(state[:drops].first[:type]).to eq(:trigger)
    end

    it "parses multiple DROP statements" do
      sql = [
        "DROP TRIGGER test_trigger ON users;",
        "DROP FUNCTION test_func();"
      ]
      state = described_class.send(:parse_sql_to_state, sql)
      expect(state[:drops].count).to eq(2)
      expect(state[:drops].map { |d| d[:type] }).to contain_exactly(:trigger, :function)
    end

    it "handles SQL that doesn't match any pattern" do
      sql = ["SELECT * FROM users;"]
      state = described_class.send(:parse_sql_to_state, sql)
      expect(state[:functions]).to be_empty
      expect(state[:triggers]).to be_empty
      expect(state[:drops]).to be_nil
    end

    it "handles mixed SQL statements" do
      sql = [
        "CREATE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();",
        "DROP TRIGGER old_trigger ON users;"
      ]
      state = described_class.send(:parse_sql_to_state, sql)
      expect(state[:functions].count).to eq(1)
      expect(state[:triggers].count).to eq(1)
      expect(state[:drops].count).to eq(1)
    end
  end

  describe ".parse_function_sql" do
    it "extracts function name and body" do
      sql = "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = described_class.send(:parse_function_sql, sql)
      expect(result[:function_name]).to eq("test_func")
      expect(result[:function_body]).to include("BEGIN RETURN NEW; END;")
    end

    it "handles function with AS body" do
      sql = "CREATE FUNCTION test_func() RETURNS TRIGGER AS 'BEGIN RETURN NEW; END;' LANGUAGE plpgsql;"
      result = described_class.send(:parse_function_sql, sql)
      expect(result[:function_name]).to eq("test_func")
    end

    it "handles function without body match (fallback to full SQL)" do
      sql = "CREATE FUNCTION test_func() RETURNS TRIGGER LANGUAGE plpgsql;"
      result = described_class.send(:parse_function_sql, sql)
      expect(result[:function_name]).to eq("test_func")
      expect(result[:function_body]).to eq(sql)
    end

    it "returns nil for non-function SQL" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_function_sql, sql)
      expect(result).to be_nil
    end
  end

  describe ".parse_trigger_sql" do
    it "extracts trigger details" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_trigger_sql, sql)
      expect(result[:trigger_name]).to eq("test_trigger")
      expect(result[:table_name]).to eq("users")
      expect(result[:timing]).to eq("BEFORE")
      expect(result[:events]).to include("INSERT")
      expect(result[:function_name]).to eq("test_func")
    end

    it "extracts multiple events" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT OR UPDATE ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_trigger_sql, sql)
      expect(result[:events]).to include("INSERT", "UPDATE")
    end

    it "extracts WHEN condition" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW WHEN (NEW.id > 0) EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_trigger_sql, sql)
      expect(result[:condition]).to eq("NEW.id > 0")
    end

    it "handles trigger without EXECUTE FUNCTION clause" do
      sql = "CREATE TRIGGER test_trigger AFTER INSERT ON users FOR EACH ROW;"
      result = described_class.send(:parse_trigger_sql, sql)
      expect(result[:trigger_name]).to eq("test_trigger")
      expect(result[:function_name]).to be_nil
      expect(result[:timing]).to eq("AFTER")
    end

    it "handles AFTER trigger timing" do
      sql = "CREATE TRIGGER test_trigger AFTER UPDATE ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_trigger_sql, sql)
      expect(result[:timing]).to eq("AFTER")
      expect(result[:events]).to include("UPDATE")
    end

    it "handles trigger without condition" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
      result = described_class.send(:parse_trigger_sql, sql)
      expect(result[:condition]).to be_nil
    end

    it "returns nil for non-trigger SQL" do
      sql = "CREATE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      result = described_class.send(:parse_trigger_sql, sql)
      expect(result).to be_nil
    end
  end

  describe ".parse_drop_sql" do
    it "parses DROP TRIGGER" do
      sql = "DROP TRIGGER test_trigger ON users;"
      result = described_class.send(:parse_drop_sql, sql)
      expect(result[:type]).to eq(:trigger)
      expect(result[:name]).to eq("test_trigger")
      expect(result[:table_name]).to eq("users")
    end

    it "parses DROP FUNCTION" do
      sql = "DROP FUNCTION test_func();"
      result = described_class.send(:parse_drop_sql, sql)
      expect(result[:type]).to eq(:function)
      expect(result[:name]).to eq("test_func")
    end

    it "handles IF EXISTS" do
      sql = "DROP TRIGGER IF EXISTS test_trigger ON users;"
      result = described_class.send(:parse_drop_sql, sql)
      expect(result[:name]).to eq("test_trigger")
    end

    it "parses DROP FUNCTION with IF EXISTS" do
      sql = "DROP FUNCTION IF EXISTS test_func();"
      result = described_class.send(:parse_drop_sql, sql)
      expect(result[:type]).to eq(:function)
      expect(result[:name]).to eq("test_func")
    end

    it "returns nil for non-DROP SQL" do
      sql = "CREATE TRIGGER test_trigger BEFORE INSERT ON users;"
      result = described_class.send(:parse_drop_sql, sql)
      expect(result).to be_nil
    end

    it "returns nil for DROP TRIGGER without proper format" do
      sql = "DROP TRIGGER invalid_format;"
      result = described_class.send(:parse_drop_sql, sql)
      expect(result).to be_nil
    end

    it "returns nil for DROP FUNCTION without proper format" do
      sql = "DROP FUNCTION invalid_format;"
      result = described_class.send(:parse_drop_sql, sql)
      expect(result).to be_nil
    end
  end

  describe ".extract_actual_state" do
    before do
      ActiveRecord::Base.connection.execute(
        "CREATE OR REPLACE FUNCTION test_actual_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
      )
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS test_users (id SERIAL PRIMARY KEY)")
      ActiveRecord::Base.connection.execute(
        "CREATE TRIGGER test_actual_trigger BEFORE INSERT ON test_users FOR EACH ROW EXECUTE FUNCTION test_actual_func();"
      )
    end

    after do
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_actual_trigger ON test_users")
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_actual_func()")
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users")
    rescue StandardError => _e
      # Ignore cleanup errors
    end

    it "extracts actual function state" do
      expected = {
        functions: [{ function_name: "test_actual_func", function_body: "test" }],
        triggers: []
      }
      actual = described_class.send(:extract_actual_state, expected)
      expect(actual[:functions]["test_actual_func"][:exists]).to be true
    end

    it "extracts actual trigger state" do
      expected = {
        functions: [],
        triggers: [{ trigger_name: "test_actual_trigger", table_name: "test_users" }]
      }
      actual = described_class.send(:extract_actual_state, expected)
      expect(actual[:triggers]["test_actual_trigger"][:exists]).to be true
    end

    it "handles non-existing objects" do
      expected = {
        functions: [{ function_name: "nonexistent_func", function_body: "test" }],
        triggers: []
      }
      actual = described_class.send(:extract_actual_state, expected)
      expect(actual[:functions]["nonexistent_func"][:exists]).to be false
    end
  end

  describe ".generate_diff" do
    it "marks new functions" do
      expected = {
        functions: [{ function_name: "new_func", function_body: "test" }],
        triggers: []
      }
      actual = {
        functions: { "new_func" => { exists: false } },
        triggers: {}
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:has_differences]).to be true
      expect(diff[:functions].first[:status]).to eq(:new)
    end

    it "marks modified functions" do
      expected = {
        functions: [{ function_name: "modified_func", function_body: "new body" }],
        triggers: []
      }
      actual = {
        functions: { "modified_func" => { exists: true, function_body: "old body" } },
        triggers: {}
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:has_differences]).to be true
      expect(diff[:functions].first[:status]).to eq(:modified)
    end

    it "marks unchanged functions" do
      expected = {
        functions: [{ function_name: "unchanged_func", function_body: "same body" }],
        triggers: []
      }
      actual = {
        functions: { "unchanged_func" => { exists: true, function_body: "same body" } },
        triggers: {}
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:has_differences]).to be false
      expect(diff[:functions].first[:status]).to eq(:unchanged)
    end

    it "marks new triggers" do
      expected = {
        functions: [],
        triggers: [{ trigger_name: "new_trigger", table_name: "users", full_sql: "CREATE TRIGGER..." }]
      }
      actual = {
        functions: {},
        triggers: { "new_trigger" => { exists: false } }
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:has_differences]).to be true
      expect(diff[:triggers].first[:status]).to eq(:new)
    end

    it "includes drops in diff" do
      expected = {
        functions: [],
        triggers: [],
        drops: [{ type: :trigger, name: "dropped_trigger" }]
      }
      actual = {
        functions: {},
        triggers: {}
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:drops]).to eq([{ type: :trigger, name: "dropped_trigger" }])
    end

    it "handles missing drops key in expected" do
      expected = {
        functions: [],
        triggers: []
      }
      actual = {
        functions: {},
        triggers: {}
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:drops]).to eq([])
    end

    it "marks modified triggers" do
      expected = {
        functions: [],
        triggers: [{
          trigger_name: "modified_trigger",
          table_name: "users",
          events: ["INSERT", "UPDATE"],
          condition: nil,
          function_name: "test_func",
          full_sql: "CREATE TRIGGER modified_trigger BEFORE INSERT OR UPDATE ON users..."
        }]
      }
      actual = {
        functions: {},
        triggers: {
          "modified_trigger" => {
            exists: true,
            trigger_name: "modified_trigger",
            table_name: "users",
            function_name: "test_func",
            trigger_definition: "CREATE TRIGGER modified_trigger BEFORE INSERT ON users..."
          }
        }
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:has_differences]).to be true
      expect(diff[:triggers].first[:status]).to eq(:modified)
      expect(diff[:triggers].first[:differences]).to be_an(Array)
    end

    it "marks unchanged triggers" do
      expected = {
        functions: [],
        triggers: [{
          trigger_name: "unchanged_trigger",
          table_name: "users",
          events: ["INSERT"],
          condition: nil,
          function_name: "test_func",
          full_sql: "CREATE TRIGGER unchanged_trigger BEFORE INSERT ON users..."
        }]
      }
      actual = {
        functions: {},
        triggers: {
          "unchanged_trigger" => {
            exists: true,
            trigger_name: "unchanged_trigger",
            table_name: "users",
            function_name: "test_func",
            trigger_definition: "CREATE TRIGGER unchanged_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
          }
        }
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:has_differences]).to be false
      expect(diff[:triggers].first[:status]).to eq(:unchanged)
    end

    it "handles function with nil actual_func" do
      expected = {
        functions: [{ function_name: "new_func", function_body: "test" }],
        triggers: []
      }
      actual = {
        functions: {},
        triggers: {}
      }
      diff = described_class.send(:generate_diff, expected, actual)
      expect(diff[:has_differences]).to be true
      expect(diff[:functions].first[:status]).to eq(:new)
    end
  end

  describe ".normalize_trigger_definition" do
    it "normalizes trigger definition" do
      trigger = {
        trigger_name: "test_trigger",
        table_name: "users",
        events: ["INSERT", "UPDATE"],
        condition: "NEW.id > 0",
        function_name: "test_func"
      }
      normalized = described_class.send(:normalize_trigger_definition, trigger)
      expect(normalized[:events]).to eq(["INSERT", "UPDATE"].sort)
    end
  end

  describe ".normalize_trigger_definition_from_db" do
    it "normalizes database trigger definition" do
      db_trigger = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT OR UPDATE ON users FOR EACH ROW EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      normalized = described_class.send(:normalize_trigger_definition_from_db, db_trigger)
      expect(normalized[:events]).to include("INSERT", "UPDATE")
    end

    it "extracts condition from definition" do
      db_trigger = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW WHEN (NEW.id > 0) EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      normalized = described_class.send(:normalize_trigger_definition_from_db, db_trigger)
      expect(normalized[:condition]).to eq("NEW.id > 0")
    end

    it "handles AFTER trigger definition" do
      db_trigger = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger AFTER UPDATE OR DELETE ON users FOR EACH ROW EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      normalized = described_class.send(:normalize_trigger_definition_from_db, db_trigger)
      expect(normalized[:events]).to include("UPDATE", "DELETE")
    end

    it "handles trigger definition without condition" do
      db_trigger = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      normalized = described_class.send(:normalize_trigger_definition_from_db, db_trigger)
      expect(normalized[:condition]).to be_nil
    end

    it "handles trigger definition without events match" do
      db_trigger = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger ON users FOR EACH ROW EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      normalized = described_class.send(:normalize_trigger_definition_from_db, db_trigger)
      expect(normalized[:events]).to eq([])
    end

    it "handles nil trigger_definition" do
      db_trigger = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: nil,
        function_name: "test_func"
      }
      normalized = described_class.send(:normalize_trigger_definition_from_db, db_trigger)
      expect(normalized[:events]).to eq([])
      expect(normalized[:condition]).to be_nil
    end
  end

  describe ".compare_trigger_details" do
    it "finds table name differences" do
      expected = { table_name: "users", events: ["INSERT"], condition: nil, function_name: "test_func" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "posts",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON posts...",
        function_name: "test_func"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to include(/Table name/)
    end

    it "finds event differences" do
      expected = { table_name: "users", events: ["INSERT", "UPDATE"], condition: nil, function_name: "test_func" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users...",
        function_name: "test_func"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to include(/Events/)
    end

    it "finds condition differences" do
      expected = { table_name: "users", events: ["INSERT"], condition: "NEW.id > 0", function_name: "test_func" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users...",
        function_name: "test_func"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to include(/Condition/)
    end

    it "finds function name differences" do
      expected = { table_name: "users", events: ["INSERT"], condition: nil, function_name: "func1" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users...",
        function_name: "func2"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to include(/Function/)
    end

    it "handles nil actual events" do
      expected = { table_name: "users", events: ["INSERT"], condition: nil, function_name: "test_func" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger ON users...",
        function_name: "test_func"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to include(/Events/)
    end

    it "returns empty array when no differences" do
      expected = { table_name: "users", events: ["INSERT"], condition: nil, function_name: "test_func" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to be_empty
    end

    it "handles condition differences with nil expected" do
      expected = { table_name: "users", events: ["INSERT"], condition: nil, function_name: "test_func" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW WHEN (NEW.id > 0) EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to include(/Condition/)
    end

    it "handles condition differences with nil actual" do
      expected = { table_name: "users", events: ["INSERT"], condition: "NEW.id > 0", function_name: "test_func" }
      actual_db = {
        trigger_name: "test_trigger",
        table_name: "users",
        trigger_definition: "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();",
        function_name: "test_func"
      }
      differences = described_class.send(:compare_trigger_details, expected, actual_db)
      expect(differences).to include(/Condition/)
    end
  end
end


