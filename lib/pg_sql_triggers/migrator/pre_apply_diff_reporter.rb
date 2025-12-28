# frozen_string_literal: true

module PgSqlTriggers
  class Migrator
    # Formats pre-apply comparison results into human-readable diff reports
    class PreApplyDiffReporter
      class << self
        # Format diff result as a string report
        def format(diff_result, migration_name: nil)
          return "No differences detected. Migration is safe to apply." unless diff_result[:has_differences]
          
          output = []
          output << "=" * 80
          output << "Pre-Apply Comparison Report"
          output << "Migration: #{migration_name}" if migration_name
          output << "=" * 80
          output << ""
          
          # Report on functions
          if diff_result[:functions].any?
            output << "Functions:"
            output << "-" * 80
            diff_result[:functions].each do |func_diff|
              output.concat(format_function_diff(func_diff))
              output << ""
            end
          end
          
          # Report on triggers
          if diff_result[:triggers].any?
            output << "Triggers:"
            output << "-" * 80
            diff_result[:triggers].each do |trigger_diff|
              output.concat(format_trigger_diff(trigger_diff))
              output << ""
            end
          end
          
          # Report on drops (for down migrations)
          if diff_result[:drops]&.any?
            output << "Drops:"
            output << "-" * 80
            diff_result[:drops].each do |drop|
              output << "  - Will #{drop[:type] == :trigger ? 'drop trigger' : 'drop function'}: #{drop[:name]}"
            end
            output << ""
          end
          
          output << "=" * 80
          output << ""
          output << "⚠️  WARNING: This migration will modify existing database objects."
          output << "Review the differences above before proceeding."
          
          output.join("\n")
        end

        # Format a concise summary for console output
        def format_summary(diff_result)
          return "✓ No differences - safe to apply" unless diff_result[:has_differences]
          
          summary = []
          summary << "⚠️  Differences detected:"
          
          new_count = diff_result[:functions].count { |f| f[:status] == :new } +
                      diff_result[:triggers].count { |t| t[:status] == :new }
          modified_count = diff_result[:functions].count { |f| f[:status] == :modified } +
                           diff_result[:triggers].count { |t| t[:status] == :modified }
          
          summary << "  - #{new_count} new object(s) will be created"
          summary << "  - #{modified_count} existing object(s) will be modified"
          
          summary.join("\n")
        end

        private

        def format_function_diff(func_diff)
          case func_diff[:status]
          when :new
            [
              "  Function: #{func_diff[:function_name]}",
              "    Status: NEW (will be created)"
            ]
          when :modified
            [
              "  Function: #{func_diff[:function_name]}",
              "    Status: MODIFIED (will overwrite existing function)",
              "    Expected:",
              indent_text(func_diff[:expected], 6),
              "    Current:",
              indent_text(func_diff[:actual], 6)
            ]
          when :unchanged
            [
              "  Function: #{func_diff[:function_name]}",
              "    Status: UNCHANGED"
            ]
          else
            [
              "  Function: #{func_diff[:function_name]}",
              "    Status: #{func_diff[:status]}"
            ]
          end
        end

        def format_trigger_diff(trigger_diff)
          case trigger_diff[:status]
          when :new
            output = []
            output << "  Trigger: #{trigger_diff[:trigger_name]}"
            output << "    Status: NEW (will be created)"
            output << "    Definition:"
            output << indent_text(trigger_diff[:expected], 6)
            output.join("\n")
          when :modified
            output = []
            output << "  Trigger: #{trigger_diff[:trigger_name]}"
            output << "    Status: MODIFIED (will overwrite existing trigger)"
            
            if trigger_diff[:differences]&.any?
              output << "    Differences:"
              trigger_diff[:differences].each do |diff|
                output << "      - #{diff}"
              end
            end
            
            output << "    Expected:"
            output << indent_text(trigger_diff[:expected], 6)
            output << "    Current:"
            output << indent_text(trigger_diff[:actual], 6)
            output.join("\n")
          when :unchanged
            output = []
            output << "  Trigger: #{trigger_diff[:trigger_name]}"
            output << "    Status: UNCHANGED"
            output.join("\n")
          else
            output = []
            output << "  Trigger: #{trigger_diff[:trigger_name]}"
            output << "    Status: #{trigger_diff[:status]}"
            output.join("\n")
          end
        end

        def indent_text(text, spaces)
          indent = " " * spaces
          text.to_s.lines.map { |line| "#{indent}#{line.chomp}" }.join("\n")
        end
      end
    end
  end
end

