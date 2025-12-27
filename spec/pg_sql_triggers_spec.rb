# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers do
  it "has a version number" do
    expect(PgSqlTriggers::VERSION).not_to be nil
    expect(PgSqlTriggers::VERSION).to be_a(String)
  end

  describe ".configure" do
    it "yields self for configuration" do
      PgSqlTriggers.configure do |config|
        expect(config).to eq(PgSqlTriggers)
      end
    end

    it "allows setting kill_switch_enabled" do
      original = PgSqlTriggers.kill_switch_enabled
      PgSqlTriggers.configure do |config|
        config.kill_switch_enabled = false
      end
      expect(PgSqlTriggers.kill_switch_enabled).to eq(false)
      PgSqlTriggers.kill_switch_enabled = original
    end

    it "allows setting default_environment" do
      original = PgSqlTriggers.default_environment
      PgSqlTriggers.configure do |config|
        config.default_environment = -> { "test" }
      end
      expect(PgSqlTriggers.default_environment.call).to eq("test")
      PgSqlTriggers.default_environment = original
    end
  end

  describe "error classes" do
    it "defines Error base class" do
      expect(PgSqlTriggers::Error).to be < StandardError
    end

    it "defines PermissionError" do
      expect(PgSqlTriggers::PermissionError).to be < PgSqlTriggers::Error
    end

    it "defines DriftError" do
      expect(PgSqlTriggers::DriftError).to be < PgSqlTriggers::Error
    end

    it "defines KillSwitchError" do
      expect(PgSqlTriggers::KillSwitchError).to be < PgSqlTriggers::Error
    end

    it "defines ValidationError" do
      expect(PgSqlTriggers::ValidationError).to be < PgSqlTriggers::Error
    end
  end
end
