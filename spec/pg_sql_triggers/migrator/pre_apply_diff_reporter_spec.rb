# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Migrator::PreApplyDiffReporter do
  describe ".format" do
    context "when no differences" do
      let(:no_diff_result) do
        {
          has_differences: false,
          functions: [],
          triggers: []
        }
      end

      it "returns appropriate message" do
        result = described_class.format(no_diff_result, migration_name: "test_migration")
        expect(result).to be_a(String)
        expect(result).to include("No differences")
      end
    end

    context "when differences exist" do
      let(:diff_result) do
        {
          has_differences: true,
          functions: [
            {
              function_name: "new_func",
              status: :new,
              expected: "CREATE FUNCTION...",
              actual: nil,
              message: "Function will be created"
            },
            {
              function_name: "modified_func",
              status: :modified,
              expected: "CREATE FUNCTION new_body...",
              actual: "CREATE FUNCTION old_body...",
              message: "Function body differs"
            }
          ],
          triggers: [
            {
              trigger_name: "new_trigger",
              status: :new,
              expected: "CREATE TRIGGER...",
              actual: nil,
              message: "Trigger will be created"
            }
          ],
          drops: [
            { type: :function, name: "dropped_func" },
            { type: :trigger, name: "dropped_trigger" }
          ]
        }
      end

      it "formats full report with differences" do
        result = described_class.format(diff_result, migration_name: "test_migration")
        expect(result).to include("Pre-Apply Comparison Report")
        expect(result).to include("test_migration")
        expect(result).to include("Functions:")
        expect(result).to include("Triggers:")
        expect(result).to include("Drops:")
        expect(result).to include("new_func")
        expect(result).to include("modified_func")
        expect(result).to include("new_trigger")
        expect(result).to include("WARNING")
      end

      it "includes function details" do
        result = described_class.format(diff_result, migration_name: "test_migration")
        expect(result).to include("new_func")
        expect(result).to include("modified_func")
      end

      it "includes trigger details" do
        result = described_class.format(diff_result, migration_name: "test_migration")
        expect(result).to include("new_trigger")
      end

      it "includes drop details" do
        result = described_class.format(diff_result, migration_name: "test_migration")
        expect(result).to include("dropped_func")
        expect(result).to include("dropped_trigger")
      end
    end

    context "without migration name" do
      let(:diff_result) do
        {
          has_differences: true,
          functions: [],
          triggers: []
        }
      end

      it "formats without migration name" do
        result = described_class.format(diff_result)
        expect(result).to include("Pre-Apply Comparison Report")
      end
    end
  end

  describe ".format_summary" do
    context "when no differences" do
      let(:no_diff_result) do
        {
          has_differences: false,
          functions: [],
          triggers: []
        }
      end

      it "returns appropriate message" do
        result = described_class.format_summary(no_diff_result)
        expect(result).to be_a(String)
        expect(result).to include("No differences")
      end
    end

    context "when differences exist" do
      let(:diff_result) do
        {
          has_differences: true,
          functions: [
            { status: :new },
            { status: :modified }
          ],
          triggers: [
            { status: :new },
            { status: :modified }
          ]
        }
      end

      it "counts new and modified objects" do
        result = described_class.format_summary(diff_result)
        expect(result).to include("Differences detected")
        expect(result).to include("new object(s)")
        expect(result).to include("modified object(s)")
      end
    end
  end

  describe ".format_function_diff" do
    it "formats new function" do
      func_diff = {
        function_name: "new_func",
        status: :new,
        expected: "CREATE FUNCTION...",
        actual: nil,
        message: "Function will be created"
      }
      result = described_class.send(:format_function_diff, func_diff)
      expect(result).to include("new_func")
      expect(result).to include("NEW")
    end

    it "formats modified function" do
      func_diff = {
        function_name: "modified_func",
        status: :modified,
        expected: "CREATE FUNCTION new_body...",
        actual: "CREATE FUNCTION old_body...",
        message: "Function body differs"
      }
      result = described_class.send(:format_function_diff, func_diff)
      expect(result).to include("modified_func")
      expect(result).to include("MODIFIED")
      expect(result).to include("Expected:")
      expect(result).to include("Current:")
    end

    it "formats unchanged function" do
      func_diff = {
        function_name: "unchanged_func",
        status: :unchanged,
        message: "Function matches"
      }
      result = described_class.send(:format_function_diff, func_diff)
      expect(result).to include("unchanged_func")
      expect(result).to include("UNCHANGED")
    end

    it "formats unknown status" do
      func_diff = {
        function_name: "unknown_func",
        status: :unknown,
        message: "Unknown status"
      }
      result = described_class.send(:format_function_diff, func_diff)
      expect(result).to include("unknown_func")
      expect(result).to include("unknown")
    end
  end

  describe ".format_trigger_diff" do
    it "formats new trigger" do
      trigger_diff = {
        trigger_name: "new_trigger",
        status: :new,
        expected: "CREATE TRIGGER...",
        actual: nil,
        message: "Trigger will be created"
      }
      result = described_class.send(:format_trigger_diff, trigger_diff)
      expect(result).to include("new_trigger")
      expect(result).to include("NEW")
      expect(result).to include("Definition:")
    end

    it "formats modified trigger" do
      trigger_diff = {
        trigger_name: "modified_trigger",
        status: :modified,
        expected: "CREATE TRIGGER new_def...",
        actual: "CREATE TRIGGER old_def...",
        message: "Trigger definition differs",
        differences: ["Table name differs", "Events differ"]
      }
      result = described_class.send(:format_trigger_diff, trigger_diff)
      expect(result).to include("modified_trigger")
      expect(result).to include("MODIFIED")
      expect(result).to include("Differences:")
      expect(result).to include("Table name differs")
      expect(result).to include("Events differ")
      expect(result).to include("Expected:")
      expect(result).to include("Current:")
    end

    it "formats modified trigger without differences array" do
      trigger_diff = {
        trigger_name: "modified_trigger",
        status: :modified,
        expected: "CREATE TRIGGER new_def...",
        actual: "CREATE TRIGGER old_def...",
        message: "Trigger definition differs"
      }
      result = described_class.send(:format_trigger_diff, trigger_diff)
      expect(result).to include("modified_trigger")
      expect(result).to include("MODIFIED")
    end

    it "formats unchanged trigger" do
      trigger_diff = {
        trigger_name: "unchanged_trigger",
        status: :unchanged,
        message: "Trigger matches"
      }
      result = described_class.send(:format_trigger_diff, trigger_diff)
      expect(result).to include("unchanged_trigger")
      expect(result).to include("UNCHANGED")
    end

    it "formats unknown status" do
      trigger_diff = {
        trigger_name: "unknown_trigger",
        status: :unknown,
        message: "Unknown status"
      }
      result = described_class.send(:format_trigger_diff, trigger_diff)
      expect(result).to include("unknown_trigger")
      expect(result).to include("unknown")
    end
  end

  describe ".indent_text" do
    it "indents text with specified spaces" do
      text = "Line 1\nLine 2\nLine 3"
      result = described_class.send(:indent_text, text, 4)
      expect(result).to include("    Line 1")
      expect(result).to include("    Line 2")
      expect(result).to include("    Line 3")
    end

    it "handles empty text" do
      result = described_class.send(:indent_text, "", 4)
      expect(result).to eq("")
    end

    it "handles nil text" do
      result = described_class.send(:indent_text, nil, 4)
      expect(result).to eq("")
    end

    it "handles single line text" do
      result = described_class.send(:indent_text, "Single line", 2)
      expect(result).to eq("  Single line")
    end
  end
end


