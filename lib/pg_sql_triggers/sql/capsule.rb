# frozen_string_literal: true

require "digest"

module PgSqlTriggers
  module SQL
    # Capsule represents a named SQL capsule with environment declaration and purpose
    # Used for emergency operations and manual SQL execution
    #
    # @example Creating a SQL capsule
    #   capsule = PgSqlTriggers::SQL::Capsule.new(
    #     name: "fix_user_permissions",
    #     environment: "production",
    #     purpose: "Emergency fix for user permission issue",
    #     sql: "UPDATE users SET role = 'admin' WHERE email = 'admin@example.com';"
    #   )
    #
    class Capsule
      attr_reader :name, :environment, :purpose, :sql, :created_at

      # @param name [String] The name of the SQL capsule
      # @param environment [String] The environment this capsule is intended for
      # @param purpose [String] Description of what this capsule does and why
      # @param sql [String] The SQL to execute
      # @param created_at [Time, nil] The timestamp when the capsule was created (defaults to now)
      def initialize(name:, environment:, purpose:, sql:, created_at: nil)
        @name = name
        @environment = environment
        @purpose = purpose
        @sql = sql
        @created_at = created_at || Time.current
        validate!
      end

      # Calculates the checksum of the SQL content
      # @return [String] The SHA256 checksum of the SQL
      def checksum
        @checksum ||= Digest::SHA256.hexdigest(sql.to_s)
      end

      # Converts the capsule to a hash suitable for storage
      # @return [Hash] The capsule data
      def to_h
        {
          name: name,
          environment: environment,
          purpose: purpose,
          sql: sql,
          checksum: checksum,
          created_at: created_at
        }
      end

      # Returns the registry trigger name for this capsule
      # SQL capsules are stored in the registry with a special naming pattern
      # @return [String] The trigger name for registry storage
      def registry_trigger_name
        "sql_capsule_#{name}"
      end

      private

      def validate!
        errors = []
        errors << "Name cannot be blank" if name.nil? || name.to_s.strip.empty?
        errors << "Environment cannot be blank" if environment.nil? || environment.to_s.strip.empty?
        errors << "Purpose cannot be blank" if purpose.nil? || purpose.to_s.strip.empty?
        errors << "SQL cannot be blank" if sql.nil? || sql.to_s.strip.empty?

        # Validate name format (alphanumeric, underscores, hyphens only)
        unless name.to_s.match?(/\A[a-z0-9_-]+\z/i)
          errors << "Name must contain only letters, numbers, underscores, and hyphens"
        end

        raise ArgumentError, "Invalid capsule: #{errors.join(', ')}" if errors.any?
      end
    end
  end
end
