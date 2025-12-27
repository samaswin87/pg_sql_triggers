# frozen_string_literal: true

module PgSqlTriggers
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
