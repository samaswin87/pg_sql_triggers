# frozen_string_literal: true

module PgTriggers
  module Audit
    class Logger
      class << self
        def log(action:, target_type:, target_name:, actor: nil, environment: nil, success: true, **options)
          actor ||= default_actor

          AuditLog.log_action(
            actor: actor,
            action: action,
            target_type: target_type,
            target_name: target_name,
            environment: environment || current_environment,
            success: success,
            **options
          )
        end

        private

        def default_actor
          {
            type: "System",
            id: "pg_triggers_gem"
          }
        end

        def current_environment
          PgTriggers.default_environment.call
        end
      end
    end
  end
end
