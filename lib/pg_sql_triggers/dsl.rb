# frozen_string_literal: true

module PgSqlTriggers
  module DSL
    autoload :TriggerDefinition, "pg_sql_triggers/dsl/trigger_definition"
    autoload :Builder, "pg_sql_triggers/dsl/builder"

    def self.pg_sql_trigger(name, &block)
      definition = TriggerDefinition.new(name)
      definition.instance_eval(&block)
      Registry.register(definition)
      definition
    end
  end
end
