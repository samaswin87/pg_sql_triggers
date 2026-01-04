# frozen_string_literal: true

module PgSqlTriggers
  class ApplicationController < ActionController::Base
    include PgSqlTriggers::Engine.routes.url_helpers

    protect_from_forgery with: :exception
    layout "pg_sql_triggers/application"

    before_action :check_permissions?

    # Include permissions helper for view helpers
    include PgSqlTriggers::PermissionsHelper

    # Helper methods available in views
    helper_method :current_environment, :kill_switch_active?, :expected_confirmation_text, :current_actor,
                  :can_view_triggers?, :can_enable_disable_triggers?, :can_drop_triggers?,
                  :can_execute_sql?, :can_generate_triggers?, :can_apply_triggers?

    private

    def check_permissions?
      # Override this method in host application to implement custom permission checks
      true
    end

    # ========== Permission Check Methods ==========

    # Check if current actor has viewer permissions
    def check_viewer_permission
      unless PgSqlTriggers::Permissions.can?(current_actor, :view_triggers, environment: current_environment)
        redirect_to root_path, alert: "Insufficient permissions. Viewer role required."
      end
    end

    # Check if current actor has operator permissions (enable/disable/apply)
    def check_operator_permission
      unless PgSqlTriggers::Permissions.can?(current_actor, :enable_trigger, environment: current_environment)
        redirect_to root_path, alert: "Insufficient permissions. Operator role required."
      end
    end

    # Check if current actor has admin permissions (drop/re-execute/execute SQL)
    def check_admin_permission
      unless PgSqlTriggers::Permissions.can?(current_actor, :drop_trigger, environment: current_environment)
        redirect_to root_path, alert: "Insufficient permissions. Admin role required."
      end
    end

    def current_actor
      # Override this in host application to provide actual user
      {
        type: current_user_type,
        id: current_user_id
      }
    end

    def current_user_type
      "User"
    end

    def current_user_id
      "unknown"
    end

    # ========== Kill Switch Helpers ==========

    # Returns the current environment
    def current_environment
      Rails.env
    end

    # Checks if kill switch is active for the current environment
    def kill_switch_active?
      PgSqlTriggers::SQL::KillSwitch.active?(environment: current_environment)
    end

    # Checks kill switch before executing a dangerous operation
    # Raises KillSwitchError if the operation is blocked
    #
    # @param operation [Symbol] The operation being performed
    # @param confirmation [String, nil] Optional confirmation text from params
    def check_kill_switch(operation:, confirmation: nil)
      PgSqlTriggers::SQL::KillSwitch.check!(
        operation: operation,
        environment: current_environment,
        confirmation: confirmation,
        actor: current_actor
      )
    end

    # Before action to require kill switch override for an action
    # Add to specific controller actions that need protection:
    #   before_action -> { require_kill_switch_override(:operation_name) }, only: [:dangerous_action]
    def require_kill_switch_override(operation, confirmation: nil)
      check_kill_switch(operation: operation, confirmation: confirmation)
    end

    # Returns the expected confirmation text for an operation (for use in views)
    def expected_confirmation_text(operation)
      if PgSqlTriggers.respond_to?(:kill_switch_confirmation_pattern) &&
         PgSqlTriggers.kill_switch_confirmation_pattern.respond_to?(:call)
        PgSqlTriggers.kill_switch_confirmation_pattern.call(operation)
      else
        "EXECUTE #{operation.to_s.upcase}"
      end
    end

    # ========== Error Handling Helpers ==========

    # Handles errors and formats them for display
    # Returns a formatted error message for flash display
    def format_error_for_flash(error)
      return error.to_s unless error.is_a?(PgSqlTriggers::Error)

      # Use user_message which includes recovery suggestions
      error.user_message
    end

    # Rescues from PgSqlTriggers errors and sets appropriate flash messages
    def rescue_pg_sql_triggers_error(error)
      Rails.logger.error("#{error.class.name}: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n")) if Rails.env.development? && error.respond_to?(:backtrace)

      if error.is_a?(PgSqlTriggers::Error)
        flash[:error] = format_error_for_flash(error)
      else
        flash[:error] = "An unexpected error occurred: #{error.message}"
      end
    end
  end
end
