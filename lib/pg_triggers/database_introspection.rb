# frozen_string_literal: true

module PgTriggers
  class DatabaseIntrospection
    # Get list of all user tables in the database
    def list_tables
      sql = <<~SQL
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
        ORDER BY table_name
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      result.map { |row| row["table_name"] }
    rescue => e
      Rails.logger.error("Failed to fetch tables: #{e.message}")
      []
    end

    # Validate that a table exists
    def validate_table(table_name)
      sql = <<~SQL
        SELECT
          COUNT(*) as column_count,
          obj_description((quote_ident(table_schema)||'.'||quote_ident(table_name))::regclass, 'pg_class') as comment
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = '#{sanitize(table_name)}'
      SQL

      result = ActiveRecord::Base.connection.execute(sql).first

      if result["column_count"].to_i > 0
        {
          valid: true,
          table_name: table_name,
          column_count: result["column_count"],
          comment: result["comment"]
        }
      else
        {
          valid: false,
          error: "Table '#{table_name}' not found in database"
        }
      end
    rescue => e
      {
        valid: false,
        error: e.message
      }
    end

    # Get table columns
    def table_columns(table_name)
      sql = <<~SQL
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = '#{sanitize(table_name)}'
        ORDER BY ordinal_position
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      result.map do |row|
        {
          name: row["column_name"],
          type: row["data_type"],
          nullable: row["is_nullable"] == "YES"
        }
      end
    end

    # Check if function exists
    def function_exists?(function_name)
      sql = <<~SQL
        SELECT COUNT(*) as count
        FROM pg_proc
        WHERE proname = '#{sanitize(function_name)}'
      SQL

      result = ActiveRecord::Base.connection.execute(sql).first
      result["count"].to_i > 0
    end

    # Check if trigger exists
    def trigger_exists?(trigger_name)
      sql = <<~SQL
        SELECT COUNT(*) as count
        FROM pg_trigger
        WHERE tgname = '#{sanitize(trigger_name)}'
      SQL

      result = ActiveRecord::Base.connection.execute(sql).first
      result["count"].to_i > 0
    end

    private

    def sanitize(value)
      ActiveRecord::Base.connection.quote_string(value.to_s)
    end
  end
end
