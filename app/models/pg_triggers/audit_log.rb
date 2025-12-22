# frozen_string_literal: true

module PgTriggers
  class AuditLog < PgTriggers::ApplicationRecord
    self.table_name = "pg_triggers_audit_logs"

    # Validations
    validates :action, presence: true
    validates :target_type, presence: true
    validates :target_name, presence: true
    validates :executed_at, presence: true
    validates :success, inclusion: { in: [true, false] }

    # Destructive actions that require a reason
    DESTRUCTIVE_ACTIONS = %w[drop execute_sql override_drift].freeze

    validates :reason, presence: true, if: -> { DESTRUCTIVE_ACTIONS.include?(action) }

    # Scopes
    scope :successful, -> { where(success: true) }
    scope :failed, -> { where(success: false) }
    scope :for_actor, ->(actor_type, actor_id) { where(actor_type: actor_type, actor_id: actor_id) }
    scope :for_target, ->(target_name) { where(target_name: target_name) }
    scope :for_action, ->(action) { where(action: action) }
    scope :recent, -> { order(executed_at: :desc) }

    # Class method to create audit log entries
    def self.log_action(actor:, action:, target_type:, target_name:, environment: nil, success: true, **options)
      create!(
        actor_type: actor[:type],
        actor_id: actor[:id],
        action: action.to_s,
        target_type: target_type.to_s,
        target_name: target_name.to_s,
        environment: environment,
        executed_at: Time.current,
        success: success,
        **options
      )
    end
  end
end
