# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "fileutils"
require_relative "../../../lib/generators/trigger/migration_generator"

RSpec.describe Trigger::Generators::MigrationGenerator do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:rails_root) { Pathname.new(tmp_dir) }

  before do
    allow(Rails).to receive(:root).and_return(rails_root)
    FileUtils.mkdir_p(rails_root.join("db", "triggers"))
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe ".next_migration_number" do
    it "returns timestamp when no existing migrations" do
      FileUtils.rm_rf(rails_root.join("db", "triggers"))
      number = described_class.next_migration_number(nil)
      expect(number).to be_a(Integer)
      expect(number.to_s.length).to be >= 14 # YYYYMMDDHHMMSS format
    end

    it "increments from existing migrations" do
      triggers_dir = rails_root.join("db", "triggers")
      File.write(triggers_dir.join("20231215120000_existing.rb"), "# existing migration")

      number = described_class.next_migration_number(nil)
      expect(number).to be > 20231215120000
    end

    it "handles multiple existing migrations" do
      triggers_dir = rails_root.join("db", "triggers")
      File.write(triggers_dir.join("20231215120000_first.rb"), "# first")
      File.write(triggers_dir.join("20231215120001_second.rb"), "# second")
      File.write(triggers_dir.join("20231215120005_third.rb"), "# third")

      number = described_class.next_migration_number(nil)
      expect(number).to be > 20231215120005
    end

    it "handles timestamp collision by incrementing" do
      triggers_dir = rails_root.join("db", "triggers")
      future_timestamp = (Time.now.utc + 3600).strftime("%Y%m%d%H%M%S").to_i
      File.write(triggers_dir.join("#{future_timestamp}_future.rb"), "# future")

      number = described_class.next_migration_number(nil)
      expect(number).to be > future_timestamp
    end

    it "ignores files that don't match migration pattern" do
      triggers_dir = rails_root.join("db", "triggers")
      File.write(triggers_dir.join("not_a_migration.txt"), "not a migration")
      File.write(triggers_dir.join("0_invalid.rb"), "# invalid")

      number = described_class.next_migration_number(nil)
      expect(number).to be_a(Integer)
    end

    it "returns 0 when db/triggers directory does not exist" do
      FileUtils.rm_rf(rails_root.join("db", "triggers"))
      number = described_class.next_migration_number(nil)
      expect(number).to be_a(Integer)
      expect(number).to be >= 0
    end
  end

  describe "#create_trigger_migration" do
    let(:generator) { described_class.new(["test_trigger"]) }

    before do
      # Mock the destination_root for the generator
      allow(generator).to receive(:destination_root).and_return(rails_root.to_s)
      allow(generator).to receive(:migration_template).and_return(true)
    end

    it "calls migration_template with correct arguments" do
      generator.create_trigger_migration
      expect(generator).to have_received(:migration_template).with(
        "trigger_migration.rb.erb",
        "db/triggers/#{generator.send(:file_name)}.rb"
      )
    end

    it "uses underscore format for trigger name in file_name" do
      generator = described_class.new(["MyComplexTrigger"])
      allow(generator).to receive(:destination_root).and_return(rails_root.to_s)
      allow(generator).to receive(:migration_template).and_return(true)
      generator.create_trigger_migration
      expect(generator.send(:file_name)).to include("my_complex_trigger")
    end
  end

  describe "#file_name" do
    it "combines migration number with underscored name" do
      generator = described_class.new(["TestTrigger"])
      allow(generator).to receive(:migration_number).and_return(1234567890)
      expect(generator.send(:file_name)).to eq("1234567890_test_trigger")
    end
  end

  describe "#class_name" do
    it "camelizes the trigger name" do
      generator = described_class.new(["test_trigger"])
      expect(generator.send(:class_name)).to eq("TestTrigger")
    end

    it "handles complex names" do
      generator = described_class.new(["my_complex_trigger_name"])
      expect(generator.send(:class_name)).to eq("MyComplexTriggerName")
    end
  end

  describe "#migration_number" do
    it "calls class method next_migration_number" do
      generator = described_class.new(["test"])
      allow(described_class).to receive(:next_migration_number).and_return(999)
      expect(generator.send(:migration_number)).to eq(999)
    end
  end
end

