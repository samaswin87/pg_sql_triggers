# frozen_string_literal: true

module PgTriggers
  class Engine < ::Rails::Engine
    isolate_namespace PgTriggers

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end

    initializer "pg_triggers.assets" do |app|
      app.config.assets.paths << root.join("app/assets")
      app.config.assets.precompile += %w[pg_triggers/application.css pg_triggers/application.js]
    end
  end
end
