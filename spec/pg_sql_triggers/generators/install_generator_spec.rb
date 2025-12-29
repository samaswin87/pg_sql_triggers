# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "fileutils"
require_relative "../../../lib/generators/pg_sql_triggers/install_generator"

RSpec.describe PgSqlTriggers::Generators::InstallGenerator do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:rails_root) { Pathname.new(tmp_dir) }

  before do
    allow(Rails).to receive(:root).and_return(rails_root)
    FileUtils.mkdir_p(rails_root.join("config", "initializers"))
    FileUtils.mkdir_p(rails_root.join("db", "migrate"))
    FileUtils.mkdir_p(rails_root.join("config"))
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe ".next_migration_number" do
    it "increments from current migration number" do
      # Create a dummy migration file
      migrate_dir = rails_root.join("db", "migrate")
      File.write(migrate_dir.join("20231215120000_existing.rb"), "# existing")

      number = described_class.next_migration_number(migrate_dir.to_s)
      expect(number).to be_a(String)
      expect(number.to_i).to be > 20_231_215_120_000
    end

    it "handles empty migration directory" do
      migrate_dir = rails_root.join("db", "migrate")
      FileUtils.rm_rf(migrate_dir)
      FileUtils.mkdir_p(migrate_dir)

      number = described_class.next_migration_number(migrate_dir.to_s)
      expect(number).to be_a(String)
    end
  end

  describe "#copy_initializer" do
    let(:generator) { described_class.new }

    before do
      allow(generator).to receive_messages(destination_root: rails_root.to_s, template: true)
    end

    it "calls template with correct arguments" do
      generator.copy_initializer
      expect(generator).to have_received(:template).with(
        "initializer.rb",
        "config/initializers/pg_sql_triggers.rb"
      )
    end
  end

  describe "#copy_migrations" do
    let(:generator) { described_class.new }

    before do
      allow(generator).to receive_messages(destination_root: rails_root.to_s, migration_template: true)
    end

    it "calls migration_template with correct arguments" do
      generator.copy_migrations
      expect(generator).to have_received(:migration_template).with(
        "create_pg_sql_triggers_tables.rb",
        "db/migrate/create_pg_sql_triggers_tables.rb"
      )
    end
  end

  describe "#mount_engine" do
    let(:generator) { described_class.new }

    before do
      allow(generator).to receive(:route).and_return(true)
    end

    it "calls route with mount statement" do
      generator.mount_engine
      expect(generator).to have_received(:route).with('mount PgSqlTriggers::Engine => "/pg_sql_triggers"')
    end
  end

  describe "#show_readme" do
    let(:generator) { described_class.new }

    it "shows readme when behavior is invoke" do
      allow(generator).to receive_messages(behavior: :invoke, readme: nil)
      generator.show_readme
      expect(generator).to have_received(:readme).with("README")
    end

    it "does not show readme when behavior is revoke" do
      allow(generator).to receive_messages(behavior: :revoke, readme: nil)
      generator.show_readme
      expect(generator).not_to have_received(:readme)
    end
  end
end
