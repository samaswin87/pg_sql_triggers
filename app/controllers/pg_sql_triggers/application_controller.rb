# frozen_string_literal: true

module PgSqlTriggers
  # Base controller for all pg_sql_triggers controllers.
  # Includes common concerns for kill switch protection, permission checking, and error handling.
  class ApplicationController < ActionController::Base
    include PgSqlTriggers::Engine.routes.url_helpers
    include PgSqlTriggers::KillSwitchProtection
    include PgSqlTriggers::PermissionChecking
    include PgSqlTriggers::ErrorHandling

    protect_from_forgery with: :exception
    layout "pg_sql_triggers/application"

    before_action :check_permissions?

    # Include permissions helper for view helpers
    include PgSqlTriggers::PermissionsHelper

    private

    # Override this method in host application to implement custom permission checks.
    #
    # @return [Boolean] true if permissions check passes
    def check_permissions?
      true
    end
  end
end
