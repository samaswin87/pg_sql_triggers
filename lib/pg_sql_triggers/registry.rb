# frozen_string_literal: true

module PgSqlTriggers
  module Registry
    autoload :Manager, "pg_sql_triggers/registry/manager"
    autoload :Validator, "pg_sql_triggers/registry/validator"

    def self.register(definition)
      Manager.register(definition)
    end

    def self.list
      Manager.list
    end

    def self.enabled
      Manager.enabled
    end

    def self.disabled
      Manager.disabled
    end

    def self.for_table(table_name)
      Manager.for_table(table_name)
    end

    def self.diff
      Manager.diff
    end

    def self.validate!
      Validator.validate!
    end

    # Console APIs for trigger operations
    # These methods provide a convenient interface for managing triggers from the Rails console

    def self.enable(trigger_name, actor:, confirmation: nil)
      check_permission!(actor, :enable_trigger)
      trigger = find_trigger!(trigger_name)
      trigger.enable!(confirmation: confirmation, actor: actor)
    end

    def self.disable(trigger_name, actor:, confirmation: nil)
      check_permission!(actor, :disable_trigger)
      trigger = find_trigger!(trigger_name)
      trigger.disable!(confirmation: confirmation, actor: actor)
    end

    def self.drop(trigger_name, actor:, reason:, confirmation: nil)
      check_permission!(actor, :drop_trigger)
      trigger = find_trigger!(trigger_name)
      trigger.drop!(reason: reason, confirmation: confirmation, actor: actor)
    end

    def self.re_execute(trigger_name, actor:, reason:, confirmation: nil)
      check_permission!(actor, :drop_trigger) # Re-execute requires same permission as drop
      trigger = find_trigger!(trigger_name)
      trigger.re_execute!(reason: reason, confirmation: confirmation, actor: actor)
    end

    # Private helper methods

    def self.find_trigger!(trigger_name)
      PgSqlTriggers::TriggerRegistry.find_by!(trigger_name: trigger_name)
    rescue ActiveRecord::RecordNotFound
      raise PgSqlTriggers::NotFoundError.new(
        "Trigger '#{trigger_name}' not found in registry",
        error_code: "TRIGGER_NOT_FOUND",
        recovery_suggestion: "Verify the trigger name or create the trigger first using the generator or DSL.",
        context: { trigger_name: trigger_name }
      )
    end
    private_class_method :find_trigger!

    def self.check_permission!(actor, action)
      PgSqlTriggers::Permissions.check!(actor, action)
    end
    private_class_method :check_permission!
  end
end
