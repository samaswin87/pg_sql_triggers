# frozen_string_literal: true

module PgSqlTriggers
  class Migration < ActiveRecord::Migration[6.0]
    # Base class for trigger migrations
    # Similar to ActiveRecord::Migration but for trigger-specific migrations

    delegate :execute, to: :connection
  end
end
