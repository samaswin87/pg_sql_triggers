# frozen_string_literal: true

module PgTriggers
  module Generator
    class Form
      include ActiveModel::Model

      attr_accessor :trigger_name, :table_name, :function_name,
                    :version, :enabled, :condition,
                    :generate_function_stub, :events, :environments

      validates :trigger_name, presence: true, format: { with: /\A[a-z0-9_]+\z/, message: "must contain only lowercase letters, numbers, and underscores" }
      validates :table_name, presence: true
      validates :function_name, presence: true, format: { with: /\A[a-z0-9_]+\z/, message: "must contain only lowercase letters, numbers, and underscores" }
      validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
      validate :at_least_one_event

      def initialize(attributes = {})
        super
        @version ||= 1
        @enabled ||= false
        @generate_function_stub = true if @generate_function_stub.nil?
        @events ||= []
        @environments ||= []
      end

      private

      def at_least_one_event
        if events.blank? || events.reject(&:blank?).empty?
          errors.add(:events, "must include at least one event")
        end
      end
    end
  end
end
