# frozen_string_literal: true

module PgTriggers
  module Audit
    autoload :Logger, "pg_triggers/audit/logger"

    def self.log(action:, target_type:, target_name:, **options)
      Logger.log(
        action: action,
        target_type: target_type,
        target_name: target_name,
        **options
      )
    end
  end
end
