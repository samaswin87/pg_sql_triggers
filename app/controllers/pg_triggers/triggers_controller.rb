# frozen_string_literal: true

module PgTriggers
  class TriggersController < ApplicationController
    before_action :set_trigger, only: [:show, :enable, :disable, :drop, :re_execute, :diff, :test_syntax, :test_dry_run, :test_safe_execute, :test_function]

    def index
      @triggers = TriggerRegistry.all.order(created_at: :desc)
    end

    def show
      @audit_logs = AuditLog.for_target(@trigger.trigger_name).recent.limit(50)
    end

    def enable
      @trigger.enable!
      audit_action(:enable, "Trigger", @trigger.trigger_name, success: true)
      redirect_to trigger_path(@trigger), notice: "Trigger enabled successfully"
    rescue StandardError => e
      audit_action(:enable, "Trigger", @trigger.trigger_name, success: false, error_message: e.message)
      redirect_to trigger_path(@trigger), alert: "Failed to enable trigger: #{e.message}"
    end

    def disable
      @trigger.disable!
      audit_action(:disable, "Trigger", @trigger.trigger_name, success: true)
      redirect_to trigger_path(@trigger), notice: "Trigger disabled successfully"
    rescue StandardError => e
      audit_action(:disable, "Trigger", @trigger.trigger_name, success: false, error_message: e.message)
      redirect_to trigger_path(@trigger), alert: "Failed to disable trigger: #{e.message}"
    end

    def drop
      reason = params[:reason]
      if reason.blank?
        redirect_to trigger_path(@trigger), alert: "Reason is required for destructive actions"
        return
      end

      @trigger.destroy!
      audit_action(:drop, "Trigger", @trigger.trigger_name, success: true, reason: reason)
      redirect_to triggers_path, notice: "Trigger dropped successfully"
    rescue StandardError => e
      audit_action(:drop, "Trigger", @trigger.trigger_name, success: false, error_message: e.message, reason: reason)
      redirect_to trigger_path(@trigger), alert: "Failed to drop trigger: #{e.message}"
    end

    def re_execute
      # This will re-apply the trigger to the database
      # Implementation will be in a separate service
      redirect_to trigger_path(@trigger), notice: "Trigger re-execution not yet implemented"
    end

    def diff
      # Show diff between DSL and actual database state
      @diff_result = PgTriggers::Drift.detect(@trigger.trigger_name)
    end

    def test_syntax
      validator = PgTriggers::Testing::SyntaxValidator.new(@trigger)
      @results = validator.validate_all

      audit_action(:test_trigger_syntax, "Trigger", @trigger.trigger_name,
                   success: @results[:overall_valid])

      render json: @results
    end

    def test_dry_run
      dry_run = PgTriggers::Testing::DryRun.new(@trigger)
      @results = dry_run.generate_sql

      audit_action(:test_trigger_dry_run, "Trigger", @trigger.trigger_name, success: true)

      render json: @results
    end

    def test_safe_execute
      executor = PgTriggers::Testing::SafeExecutor.new(@trigger)
      test_data = JSON.parse(params[:test_data]) rescue nil
      @results = executor.test_execute(test_data: test_data)

      audit_action(:test_trigger_safe_execute, "Trigger", @trigger.trigger_name,
                   success: @results[:success])

      render json: @results
    end

    def test_function
      tester = PgTriggers::Testing::FunctionTester.new(@trigger)
      @results = tester.test_function_only

      definition = JSON.parse(@trigger.definition)
      audit_action(:test_function, "Function", definition["function_name"],
                   success: @results[:success])

      render json: @results
    end

    private

    def set_trigger
      @trigger = TriggerRegistry.find(params[:id])
    end
  end
end
