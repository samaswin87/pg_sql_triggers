# frozen_string_literal: true

class CreatePgTriggersTables < ActiveRecord::Migration[6.0]
  def change
    # Registry table - source of truth for all triggers
    create_table :pg_triggers_registry do |t|
      t.string :trigger_name, null: false
      t.string :table_name, null: false
      t.integer :version, null: false, default: 1
      t.boolean :enabled, null: false, default: false
      t.string :checksum, null: false
      t.string :source, null: false # dsl, generated, manual_sql
      t.string :environment
      t.text :definition # Stored DSL or SQL definition
      t.text :function_body # The actual function body
      t.text :condition # Optional WHEN clause condition
      t.datetime :installed_at
      t.datetime :last_verified_at

      t.timestamps
    end

    add_index :pg_triggers_registry, :trigger_name, unique: true
    add_index :pg_triggers_registry, :table_name
    add_index :pg_triggers_registry, :enabled
    add_index :pg_triggers_registry, :source
    add_index :pg_triggers_registry, :environment

    # Audit log - append-only log of all mutations
    create_table :pg_triggers_audit_logs do |t|
      t.string :actor_type # User, System, Console, CLI, UI
      t.string :actor_id
      t.string :action, null: false # enable, disable, drop, apply, execute_sql, etc.
      t.string :target_type, null: false # Trigger, SQLCapsule, Function
      t.string :target_name, null: false
      t.string :environment
      t.string :source # dsl, manual_sql, etc.
      t.string :checksum_before
      t.string :checksum_after
      t.text :reason # Required for destructive actions
      t.datetime :executed_at, null: false
      t.boolean :success, null: false, default: false
      t.text :error_message
      t.text :metadata # JSON field for additional context

      t.timestamps
    end

    add_index :pg_triggers_audit_logs, :actor_type
    add_index :pg_triggers_audit_logs, :action
    add_index :pg_triggers_audit_logs, :target_name
    add_index :pg_triggers_audit_logs, :environment
    add_index :pg_triggers_audit_logs, :executed_at
    add_index :pg_triggers_audit_logs, :success
  end
end
