# frozen_string_literal: true

module DatabaseHelpers
  # Creates a test table with standard columns
  # @param table_name [Symbol, String] The name of the table to create
  # @param columns [Hash] Additional columns to add (name => type)
  # @return [void]
  def create_test_table(table_name, columns: {})
    return if ActiveRecord::Base.connection.table_exists?(table_name)

    ActiveRecord::Base.connection.create_table table_name do |t|
      columns.each do |name, type|
        t.send(type, name)
      end
      t.timestamps
    end
  end

  # Drops a test table if it exists
  # @param table_name [Symbol, String] The name of the table to drop
  # @return [void]
  def drop_test_table(table_name)
    ActiveRecord::Base.connection.drop_table(table_name) if ActiveRecord::Base.connection.table_exists?(table_name)
  end

  # Creates a standard users table for testing
  # @return [void]
  def create_users_table
    create_test_table(:users, columns: { name: :string, email: :string })
  end

  # Creates a standard posts table for testing
  # @return [void]
  def create_posts_table
    create_test_table(:posts, columns: { title: :string, body: :text, user_id: :integer })
  end

  # Ensures a table exists for the duration of a block, then cleans up
  # @param table_name [Symbol, String] The name of the table
  # @param columns [Hash] Columns to add to the table
  # @yield The block to execute with the table present
  # @return [void]
  def with_test_table(table_name, columns: {})
    create_test_table(table_name, columns: columns)
    yield
  ensure
    drop_test_table(table_name)
  end
end

RSpec.configure do |config|
  config.include DatabaseHelpers
end
