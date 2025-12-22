# frozen_string_literal: true

PgTriggers.configure do |config|
  # Enable or disable the production kill switch
  # When enabled, all destructive operations in production require explicit confirmation
  config.kill_switch_enabled = true

  # Set the default environment detection
  # By default, uses Rails.env
  config.default_environment = -> { Rails.env }

  # Set a custom permission checker
  # This should return true/false based on the actor, action, and environment
  # Example:
  # config.permission_checker = ->(actor, action, environment) {
  #   # Your custom permission logic here
  #   # e.g., check if actor has required role for the action
  #   true
  # }
  config.permission_checker = nil
end
