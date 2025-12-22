# frozen_string_literal: true

module PgTriggers
  class TriggerRegistry < PgTriggers::ApplicationRecord
    self.table_name = "pg_triggers_registry"

    # Validations
    validates :trigger_name, presence: true, uniqueness: true
    validates :table_name, presence: true
    validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :checksum, presence: true
    validates :source, presence: true, inclusion: { in: %w[dsl generated manual_sql] }

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :for_table, ->(table_name) { where(table_name: table_name) }
    scope :for_environment, ->(env) { where(environment: [env, nil]) }
    scope :by_source, ->(source) { where(source: source) }

    # Drift states
    def drift_state
      # This will be implemented by the Drift::Detector
      PgTriggers::Drift.detect(trigger_name)
    end

    def enable!
      update!(enabled: true)
    end

    def disable!
      update!(enabled: false)
    end

    def calculate_checksum
      Digest::SHA256.hexdigest([trigger_name, table_name, version, function_body, condition].join)
    end

    def verify!
      update!(last_verified_at: Time.current)
    end
  end
end
