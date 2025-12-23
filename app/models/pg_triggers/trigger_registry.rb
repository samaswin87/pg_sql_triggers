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
      # Enable the trigger in PostgreSQL
      sql = "ALTER TABLE #{quote_identifier(table_name)} ENABLE TRIGGER #{quote_identifier(trigger_name)};"
      ActiveRecord::Base.connection.execute(sql)
      
      # Update the registry record
      update!(enabled: true)
    rescue ActiveRecord::StatementInvalid => e
      # If trigger doesn't exist in database, just update registry
      # This allows enabling triggers that haven't been installed yet
      if e.message.include?("does not exist")
        update!(enabled: true)
      else
        raise
      end
    end

    def disable!
      # Disable the trigger in PostgreSQL
      sql = "ALTER TABLE #{quote_identifier(table_name)} DISABLE TRIGGER #{quote_identifier(trigger_name)};"
      ActiveRecord::Base.connection.execute(sql)
      
      # Update the registry record
      update!(enabled: false)
    rescue ActiveRecord::StatementInvalid => e
      # If trigger doesn't exist in database, just update registry
      # This allows disabling triggers that haven't been installed yet
      if e.message.include?("does not exist")
        update!(enabled: false)
      else
        raise
      end
    end

    private

    def quote_identifier(identifier)
      ActiveRecord::Base.connection.quote_table_name(identifier.to_s)
    end

    def calculate_checksum
      Digest::SHA256.hexdigest([trigger_name, table_name, version, function_body, condition].join)
    end

    def verify!
      update!(last_verified_at: Time.current)
    end
  end
end
