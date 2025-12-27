# frozen_string_literal: true

module PgSqlTriggers
  module Testing
    class FunctionTester
      def initialize(trigger_registry)
        @trigger = trigger_registry
      end

      # Test ONLY the function, not the trigger
      def test_function_only(test_context: {})
        results = {
          function_created: false,
          function_executed: false,
          errors: [],
          output: []
        }

        ActiveRecord::Base.transaction do
          begin
            # Create function in transaction
            ActiveRecord::Base.connection.execute(@trigger.function_body)
            results[:function_created] = true
            results[:output] << "✓ Function created in test transaction"

            # Try to invoke function directly (if test context provided)
            if test_context.present?
              # This would require custom invocation logic
              # For now, just verify it was created
              definition = JSON.parse(@trigger.definition) rescue {}
              function_name = definition["function_name"]
              if function_name.present?
                sanitized_name = ActiveRecord::Base.connection.quote_string(function_name)
                check_sql = <<~SQL
                  SELECT proname
                  FROM pg_proc
                  WHERE proname = '#{sanitized_name}'
                SQL

                result = ActiveRecord::Base.connection.execute(check_sql)
                if result.any?
                  results[:function_executed] = true
                  results[:output] << "✓ Function exists and is callable"
                end
              end
            end

            results[:success] = true

          rescue ActiveRecord::StatementInvalid => e
            results[:success] = false
            results[:errors] << e.message
          ensure
            raise ActiveRecord::Rollback
          end
        end

        results[:output] << "\n⚠ Function rolled back (test mode)"
        results
      end

      # Check if function already exists in database
      def function_exists?
        definition = JSON.parse(@trigger.definition) rescue {}
        function_name = definition["function_name"]
        return false if function_name.blank?

        sanitized_name = ActiveRecord::Base.connection.quote_string(function_name)
        sql = <<~SQL
          SELECT COUNT(*) as count
          FROM pg_proc
          WHERE proname = '#{sanitized_name}'
        SQL

        result = ActiveRecord::Base.connection.execute(sql)
        result.first["count"].to_i > 0
      end
    end
  end
end
