# frozen_string_literal: true

module PgTriggers
  class DashboardController < ApplicationController
    def index
      @triggers = TriggerRegistry.all.order(created_at: :desc)
      @stats = {
        total: @triggers.count,
        enabled: @triggers.enabled.count,
        disabled: @triggers.disabled.count,
        drifted: 0 # Will be calculated by Drift::Detector
      }
    end
  end
end
