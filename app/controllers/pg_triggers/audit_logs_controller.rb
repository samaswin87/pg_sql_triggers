# frozen_string_literal: true

module PgTriggers
  class AuditLogsController < ApplicationController
    def index
      @audit_logs = AuditLog.recent.page(params[:page]).per(50)

      # Filter by action if provided
      @audit_logs = @audit_logs.for_action(params[:action_filter]) if params[:action_filter].present?

      # Filter by success status if provided
      @audit_logs = @audit_logs.successful if params[:success] == "true"
      @audit_logs = @audit_logs.failed if params[:success] == "false"
    end

    def show
      @audit_log = AuditLog.find(params[:id])
    end
  end
end
