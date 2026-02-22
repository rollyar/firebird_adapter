# frozen_string_literal: true

require "bundler/setup"
require "active_record"
require "fb"
require "firebird_adapter"
require "rspec"

is_ci = ENV["FIREBIRD_HOST"] || ENV["CI"] == "true"

DB_PATH = if is_ci
            "/tmp/test.fdb"
          else
            ENV["FIREBIRD_DATABASE"] || File.expand_path("test.fdb", __dir__)
          end

if is_ci
  begin
    ::Fb::Database.create(
      database: "localhost:#{DB_PATH}",
      user: "SYSDBA",
      password: "masterkey"
    )
    puts "✓ Remote test database created at #{DB_PATH}"
  rescue StandardError => e
    puts "Note: Database may already exist: #{e.message}"
  end

  DB_CONFIG = {
    adapter: "firebird",
    database: "localhost:#{DB_PATH}",
    username: "SYSDBA",
    password: "masterkey",
    charset: "UTF8"
  }.freeze
else
  DB_CONFIG = {
    adapter: "firebird",
    database: DB_PATH,
    username: ENV["FIREBIRD_USER"] || "sysdba",
    password: ENV["FIREBIRD_PASSWORD"] || "masterkey",
    charset: "UTF8",
    downcase: false
  }.freeze

  File.delete(DB_PATH) if File.exist?(DB_PATH)

  begin
    ::Fb::Database.create(
      database: DB_PATH,
      user: "SYSDBA",
      password: "masterkey"
    )
    puts "✓ Test database created at #{DB_PATH}"
  rescue StandardError => e
    puts "Note: Database may already exist: #{e.message}"
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus

  config.before(:suite) do
    ActiveRecord::Base.establish_connection(DB_CONFIG)
    connection = ActiveRecord::Base.connection

    # ✅ CORREGIDO: Usar create_table en lugar de SQL directo
    unless connection.table_exists?(:sis_tests)
      connection.create_table :sis_tests, force: true, id: :bigint do |t|
        t.text :field_varchar
        t.string :field_char, limit: 10
        t.date :field_date
        t.integer :field_smallint
        t.integer :field_integer
        t.float :field_double_precision
        t.text :field_blob_text
        t.binary :field_blob_binary
        t.boolean :field_boolean
        t.decimal :field_decimal, precision: 10, scale: 2
        t.timestamps
      end
      puts "✓ Test table SIS_TESTS created"
    end

    unless defined?(SisTest)
      class SisTest < ActiveRecord::Base
        self.table_name = "sis_tests"
        self.primary_key = "id"
      end
    end

    SisTest.reset_column_information
  end

  config.after(:suite) do
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
    unless is_ci
      db_path = DB_CONFIG[:database]
      File.delete(db_path) if File.exist?(db_path)
    end
    puts "✓ Test cleanup completed"
  rescue StandardError
    nil
  end

  config.before(:each) do
    begin
      ActiveRecord::Base.establish_connection(DB_CONFIG) unless ActiveRecord::Base.connection.active?
    rescue StandardError
      ActiveRecord::Base.establish_connection(DB_CONFIG)
    end

    connection = ActiveRecord::Base.connection
    begin
      connection.rollback_db_transaction if connection.transaction_open?
    rescue StandardError
      nil
    end

    SisTest.delete_all if connection.table_exists?(:sis_tests)
    SisTest.reset_column_information if defined?(SisTest)
  end
end
