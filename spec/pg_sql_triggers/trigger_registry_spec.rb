# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::TriggerRegistry do
  describe "validations" do
    it "requires trigger_name" do
      registry = described_class.new(
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:trigger_name]).to include("can't be blank")
    end

    it "requires unique trigger_name" do
      described_class.create!(
        trigger_name: "unique_trigger",
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )

      registry = described_class.new(
        trigger_name: "unique_trigger",
        table_name: "posts",
        version: 1,
        checksum: "def",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:trigger_name]).to include("has already been taken")
    end

    it "requires table_name" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        version: 1,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:table_name]).to include("can't be blank")
    end

    it "requires version to be present and positive integer" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        version: nil,
        checksum: "abc",
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:version]).to include("can't be blank")

      registry.version = 0
      expect(registry).not_to be_valid
      expect(registry.errors[:version]).to include("must be greater than 0")

      registry.version = -1
      expect(registry).not_to be_valid

      registry.version = 1
      expect(registry).to be_valid
    end

    it "requires checksum" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        source: "dsl"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:checksum]).to include("can't be blank")
    end

    it "requires source to be one of valid values" do
      registry = described_class.new(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        checksum: "abc",
        source: "invalid"
      )
      expect(registry).not_to be_valid
      expect(registry.errors[:source]).to include("is not included in the list")

      %w[dsl generated manual_sql].each do |source|
        registry.source = source
        expect(registry).to be_valid
      end
    end
  end

  describe "scopes" do
    before do
      described_class.create!(
        trigger_name: "enabled1",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
      described_class.create!(
        trigger_name: "enabled2",
        table_name: "posts",
        version: 1,
        enabled: true,
        checksum: "def",
        source: "dsl"
      )
      described_class.create!(
        trigger_name: "disabled1",
        table_name: "comments",
        version: 1,
        enabled: false,
        checksum: "ghi",
        source: "dsl"
      )
    end

    describe ".enabled" do
      it "returns only enabled triggers" do
        result = described_class.enabled
        expect(result.count).to eq(2)
        expect(result.map(&:trigger_name)).to contain_exactly("enabled1", "enabled2")
      end
    end

    describe ".disabled" do
      it "returns only disabled triggers" do
        result = described_class.disabled
        expect(result.count).to eq(1)
        expect(result.first.trigger_name).to eq("disabled1")
      end
    end

    describe ".for_table" do
      it "returns triggers for specific table" do
        result = described_class.for_table("users")
        expect(result.count).to eq(1)
        expect(result.first.trigger_name).to eq("enabled1")
      end
    end

    describe ".for_environment" do
      before do
        described_class.create!(
          trigger_name: "prod_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "jkl",
          source: "dsl",
          environment: "production"
        )
        described_class.create!(
          trigger_name: "no_env_trigger",
          table_name: "posts",
          version: 1,
          enabled: true,
          checksum: "mno",
          source: "dsl",
          environment: nil
        )
      end

      it "returns triggers for specific environment or nil" do
        result = described_class.for_environment("production")
        expect(result.map(&:trigger_name)).to include("prod_trigger", "no_env_trigger")
      end
    end

    describe ".by_source" do
      before do
        described_class.create!(
          trigger_name: "generated_trigger",
          table_name: "users",
          version: 1,
          enabled: true,
          checksum: "pqr",
          source: "generated"
        )
      end

      it "returns triggers by source" do
        dsl_triggers = described_class.by_source("dsl")
        expect(dsl_triggers.count).to eq(3)

        generated_triggers = described_class.by_source("generated")
        expect(generated_triggers.count).to eq(1)
        expect(generated_triggers.first.trigger_name).to eq("generated_trigger")
      end
    end
  end

  describe "#drift_state" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "delegates to Drift.detect" do
      allow(PgSqlTriggers::Drift).to receive(:detect).with("test_trigger").and_return({ state: :in_sync })
      expect(registry.drift_state).to eq(:in_sync)
    end
  end

  describe "#enable!" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "abc",
        source: "dsl"
      )
    end

    context "when trigger exists in database" do
      before do
        # Create a test table and trigger
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")
        begin
          ActiveRecord::Base.connection.execute("CREATE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
          ActiveRecord::Base.connection.execute("CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_function();")
        rescue StandardError
          # Trigger might already exist
        end
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON users")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
      rescue StandardError => _e
        # Ignore errors during cleanup - trigger/function may not exist
      end

      it "enables the trigger in database" do
        registry.enable!
        expect(registry.enabled).to be(true)
        expect(registry.reload.enabled).to be(true)
      end
    end

    context "when trigger doesn't exist in database" do
      it "updates registry even if trigger doesn't exist" do
        expect { registry.enable! }.not_to raise_error
        expect(registry.reload.enabled).to be(true)
      end
    end
  end

  describe "#disable!" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    context "when trigger exists in database" do
      before do
        ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")
        begin
          ActiveRecord::Base.connection.execute("CREATE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;")
          ActiveRecord::Base.connection.execute("CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_function();")
        rescue StandardError
          # Trigger might already exist
        end
      end

      after do
        ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS test_trigger ON users")
        ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS test_function()")
      rescue StandardError => _e
        # Ignore errors during cleanup - trigger/function may not exist
      end

      it "disables the trigger in database" do
        registry.disable!
        expect(registry.enabled).to be(false)
        expect(registry.reload.enabled).to be(false)
      end
    end

    context "when trigger doesn't exist in database" do
      it "updates registry even if trigger doesn't exist" do
        expect { registry.disable! }.not_to raise_error
        expect(registry.reload.enabled).to be(false)
      end
    end

    it "checks kill switch before disabling" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_disable,
        environment: Rails.env,
        confirmation: nil,
        actor: { type: "Console", id: "TriggerRegistry#disable!" }
      )
      registry.disable!
    end

    it "uses explicit confirmation when provided" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_disable,
        environment: Rails.env,
        confirmation: "custom_confirmation",
        actor: { type: "Console", id: "TriggerRegistry#disable!" }
      )
      registry.disable!(confirmation: "custom_confirmation")
    end

    it "handles errors when checking trigger existence" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_raise(StandardError.new("DB error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect { registry.disable! }.not_to raise_error
      expect(registry.reload.enabled).to be(false)
    end

    it "handles errors when disabling trigger in database" do
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY)")
      # Ensure registry is created before setting up the mock
      registry # Force evaluation of let(:registry) before mock is set up
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::StatementInvalid.new("Error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(PgSqlTriggers::DatabaseIntrospection).to receive(:trigger_exists?).and_return(true)
      # rubocop:enable RSpec/AnyInstance
      expect { registry.disable! }.not_to raise_error
      expect(registry.reload.enabled).to be(false)
    end
  end

  describe "#drift_result" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "delegates to Drift::Detector.detect" do
      allow(PgSqlTriggers::Drift::Detector).to receive(:detect).with("test_trigger").and_return({ state: :in_sync })
      expect(registry.drift_result).to eq({ state: :in_sync })
    end
  end

  describe "#drifted?" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "returns true when drift_state is drifted" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_DRIFTED)
      expect(registry.drifted?).to be true
    end

    it "returns false when drift_state is not drifted" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
      expect(registry.drifted?).to be false
    end
  end

  describe "#in_sync?" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "returns true when drift_state is in_sync" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
      expect(registry.in_sync?).to be true
    end

    it "returns false when drift_state is not in_sync" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_DRIFTED)
      expect(registry.in_sync?).to be false
    end
  end

  describe "#dropped?" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: true,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "returns true when drift_state is dropped" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_DROPPED)
      expect(registry.dropped?).to be true
    end

    it "returns false when drift_state is not dropped" do
      allow(registry).to receive(:drift_state).and_return(PgSqlTriggers::DRIFT_STATE_IN_SYNC)
      expect(registry.dropped?).to be false
    end
  end

  describe "#enable! edge cases" do
    let(:registry) do
      described_class.create!(
        trigger_name: "test_trigger",
        table_name: "users",
        version: 1,
        enabled: false,
        checksum: "abc",
        source: "dsl"
      )
    end

    it "checks kill switch before enabling" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_enable,
        environment: Rails.env,
        confirmation: nil,
        actor: { type: "Console", id: "TriggerRegistry#enable!" }
      )
      registry.enable!
    end

    it "uses explicit confirmation when provided" do
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).with(
        operation: :trigger_enable,
        environment: Rails.env,
        confirmation: "custom_confirmation",
        actor: { type: "Console", id: "TriggerRegistry#enable!" }
      )
      registry.enable!(confirmation: "custom_confirmation")
    end

    it "handles errors when checking trigger existence" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_raise(StandardError.new("DB error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      expect { registry.enable! }.not_to raise_error
      expect(registry.reload.enabled).to be(true)
    end

    it "handles errors when enabling trigger in database" do
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY)")
      # Ensure registry is created before setting up the mock
      registry # Force evaluation of let(:registry) before mock is set up
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::StatementInvalid.new("Error"))
      allow(PgSqlTriggers::SQL::KillSwitch).to receive(:check!).and_return(true)
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(PgSqlTriggers::DatabaseIntrospection).to receive(:trigger_exists?).and_return(true)
      # rubocop:enable RSpec/AnyInstance
      expect { registry.enable! }.not_to raise_error
      expect(registry.reload.enabled).to be(true)
    end
  end
end
