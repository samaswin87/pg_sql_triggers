# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Engine do
  describe "configuration" do
    it "isolates namespace" do
      expect(described_class.isolated?).to be true
      expect(described_class.isolated_namespace).to eq(PgSqlTriggers)
    end

    it "configures generators" do
      expect(described_class.config.generators.test_framework).to eq(:rspec)
      expect(described_class.config.generators.fixture_replacement).to eq(:factory_bot)
      expect(described_class.config.generators.factory_bot.dir).to eq("spec/factories")
    end
  end

  describe "assets configuration" do
    let(:app) { double("Rails::Application") }
    let(:config) { double("Rails::Application::Configuration") }
    let(:assets) { double(paths: [], precompile: []) }

    before do
      allow(app).to receive(:config).and_return(config)
    end

    it "adds asset paths when assets are available" do
      allow(config).to receive(:respond_to?).with(:assets).and_return(true)
      allow(config).to receive(:assets).and_return(assets)
      
      initializer = described_class.initializers.find { |i| i.name == "pg_sql_triggers.assets" }
      expect(initializer).to be_present
      
      initializer.block.call(app)
      
      expect(assets.paths).to include(described_class.root.join("app/assets/stylesheets").to_s)
      expect(assets.paths).to include(described_class.root.join("app/assets/javascripts").to_s)
      expect(assets.precompile).to include("pg_sql_triggers/application.css")
      expect(assets.precompile).to include("pg_sql_triggers/application.js")
    end

    it "skips asset configuration when assets not available" do
      allow(config).to receive(:respond_to?).with(:assets).and_return(false)
      
      initializer = described_class.initializers.find { |i| i.name == "pg_sql_triggers.assets" }
      expect(initializer).to be_present
      
      expect { initializer.block.call(app) }.not_to raise_error
    end
  end

  describe "rake tasks" do
    it "loads rake tasks" do
      rake_tasks_block = described_class.rake_tasks_block
      expect(rake_tasks_block).to be_present
      
      # Verify the task file exists
      task_file = described_class.root.join("lib/tasks/trigger_migrations.rake")
      expect(File.exist?(task_file)).to be true
    end
  end
end

