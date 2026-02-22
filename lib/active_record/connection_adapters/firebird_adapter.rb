# frozen_string_literal: true

require "active_record/connection_adapters/abstract_adapter"
require "active_record/connection_adapters/statement_pool"
require "fb"
require "active_record/connection_adapters/firebird/connection"
require "active_record/connection_adapters/firebird/database_statements"
require "active_record/connection_adapters/firebird/schema_statements"
require "active_record/connection_adapters/firebird/quoting"
require "active_record/connection_adapters/firebird/schema_definitions"
require "active_record/connection_adapters/firebird/column"
require "active_record/connection_adapters/firebird/type_metadata"

module ActiveRecord
  module ConnectionAdapters
    # = Active Record Firebird Adapter
    #
    # Supports Firebird 3.0+, 4.0+, 5.0+ using the fb gem (https://github.com/rowland/fb)
    class Version
      include Comparable

      attr_reader :full_version_string, :version

      def initialize(version_number, version_string = nil)
        @version = version_number.to_s.scan(/(\d{2})(\d{2})(\d{3})/).first.map(&:to_i)
        @full_version_string = version_string
      end

      def <=>(other)
        return unless other.respond_to?(:version)

        @version <=> other.version
      end

      def to_s
        "#{@version[0]}.#{@version[1]}.#{@version[2]}"
      end

      # ✅ CORREGIDO: Sintaxis válida para acceso a array
      def major = @version[0]
      def minor = @version[1]
      def patch = @version[2]
    end

    class FirebirdAdapter < AbstractAdapter
      ADAPTER_NAME = "Firebird"
      DEFAULT_ENCODING = "UTF8"

      include Firebird::DatabaseStatements
      include Firebird::SchemaStatements
      include Firebird::Quoting

      class_attribute :emulate_booleans, default: true
      class_attribute :datetime_with_timezone, default: true

      def initialize(config)
        super
        @config = config
        @connection_parameters = config.symbolize_keys

        @firebird_version = nil
        @supports_skip_locked = nil
        @supports_partial_indexes = nil
        @supports_parallel_workers = nil
        @supports_time_zones = nil
        @connection = nil

        @downcase_columns = if @connection_parameters.key?(:downcase)
                              @connection_parameters[:downcase]
                            else
                              @connection_parameters[:downcase_columns] || false
                            end
      end

      def downcase_columns?
        !!@downcase_columns
      end

      def connect
        return @connection if @connection && active?

        begin
          @connection = ::Fb::Database.connect(@connection_parameters)
        rescue ::Fb::Error => e
          raise ConnectionNotEstablished, "Failed to connect to Firebird: #{e.message}"
        end

        @connection
      end

      def disconnect!
        super
        @connection&.close
      rescue StandardError
        nil
      end
      alias disconnect disconnect!

      def active?
        @connection&.open?
      end

      def verify!
        connect unless active?
      end

      def reconnect!
        disconnect!
        connect
      end
      alias reconnect reconnect!

      def transaction_open?
        @connection&.transaction_started
      end
      alias transaction_active? transaction_open?

      def discard!
        @connection = nil
      end

      # ========== CAPABILITIES ==========
      def supports_migrations? = true
      def supports_primary_key? = true
      def supports_bulk_alter? = false
      def supports_foreign_keys? = true
      def supports_check_constraints? = true
      def supports_views? = true
      def supports_datetime_with_precision? = firebird_version >= 40_000
      def supports_json? = true
      def supports_uuid? = true
      def supports_savepoints? = true
      def supports_transaction_isolation? = true
      def supports_partial_index? = firebird_version >= 50_000
      def supports_expression_index? = true
      def supports_insert_returning? = true
      def supports_insert_on_conflict? = firebird_version >= 40_000
      alias supports_insert_on_duplicate_skip? supports_insert_on_conflict?
      alias supports_insert_on_duplicate_update? supports_insert_on_conflict?
      def supports_optimizer_hints? = true
      def supports_common_table_expressions? = true
      def supports_window_functions? = true
      def supports_lazy_transactions? = false
      def supports_advisory_locks? = false
      def supports_virtual_columns? = true
      def supports_comments? = true
      def supports_comments_in_create? = false
      def supports_skip_locked? = firebird_version >= 50_000
      def supports_nulls_not_distinct? = false
      def supports_concurrent_connections? = true
      def supports_time_zones? = firebird_version >= 40_000
      def supports_int128? = firebird_version >= 40_000
      def supports_parallel_workers? = firebird_version >= 50_000
      def supports_profiler? = firebird_version >= 50_000
      def supports_identity_columns? = firebird_version >= 30_000
      def supports_multi_insert? = true
      def supports_concurrent_index? = false
      def supports_foreign_keys_in_create? = true
      def supports_deferrable_constraints? = false
      def supports_decfloat? = firebird_version >= 40_000
      def supports_boolean_type? = firebird_version >= 30_000
      def supports_timestamp_with_timezone? = firebird_version >= 40_000
      def supports_explain? = true

      # ========== VERSION DETECTION ==========
      def firebird_version
        return @firebird_version if @firebird_version

        begin
          version_result = query_value(<<~SQL.squish)
            SELECT RDB$GET_CONTEXT('SYSTEM', 'ENGINE_VERSION')
            FROM RDB$DATABASE
          SQL

          version_string = case version_result
                           when Array then version_result.first.to_s
                           when nil then "3.0.0"
                           else version_result.to_s
                           end

          if version_string =~ /(\d+)\.(\d+)\.(\d+)/
            major = Regexp.last_match(1).to_i
            minor = Regexp.last_match(2).to_i
            patch = Regexp.last_match(3).to_i
            @firebird_version = (major * 10_000) + (minor * 100) + patch
            @firebird_version_string = version_string
          else
            @firebird_version = 30_000
            @firebird_version_string = "3.0.0"
          end

          @firebird_version
        rescue StandardError
          @firebird_version = 30_000
          @firebird_version_string = "3.0.0"
        end
      end

      def firebird_version_string
        @firebird_version_string || firebird_version.to_s
      end

      def database_version
        Version.new(@firebird_version, firebird_version_string)
      end

      # ========== CRITICAL: IDENTITY COLUMN SUPPORT ==========
      def native_database_types
        types = super

        # ✅ CRITICAL: Force IDENTITY syntax for Firebird 3+/4+/5+
        types[:primary_key] = "BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY"

        # Firebird-specific types (conditional by version)
        types[:boolean] = { name: "BOOLEAN" } if supports_boolean_type?
        types[:decfloat] = { name: "DECFLOAT" } if supports_decfloat?
        types[:time_with_timezone] = { name: "TIME WITH TIME ZONE" } if supports_time_zones?
        types[:timestamp_with_timezone] = { name: "TIMESTAMP WITH TIME ZONE" } if supports_timestamp_with_timezone?
        types[:int128] = { name: "INT128" } if supports_int128?

        # Basic types (always available)
        types[:string] = { name: "VARCHAR", limit: 255 }
        types[:text] = { name: "BLOB SUB_TYPE TEXT" }
        types[:integer] = { name: "INTEGER" }
        types[:bigint] = { name: "BIGINT" }
        types[:float] = { name: "FLOAT" }
        types[:decimal] = { name: "DECIMAL" }
        types[:numeric] = { name: "NUMERIC" }
        types[:datetime] = { name: "TIMESTAMP" }
        types[:timestamp] = { name: "TIMESTAMP" }
        types[:date] = { name: "DATE" }
        types[:time] = { name: "TIME" }
        types[:binary] = { name: "BLOB SUB_TYPE BINARY" }
        types[:json] = { name: "BLOB SUB_TYPE TEXT" }
        types[:uuid] = { name: "CHAR(16) CHARACTER SET OCTETS" }

        types
      end

      # CRITICAL: Tell Rails to omit PK column in INSERTs (Firebird handles it via IDENTITY)
      def prefers_identity_insert?(_primary_key = nil)
        true
      end

      def return_value_after_insert?(column)
        column.respond_to?(:computed_source) && column.computed_source&.include?("IDENTITY") ||
          column.sql_type&.include?("IDENTITY") ||
          column.respond_to?(:auto_populated?) && column.auto_populated? ||
          column.respond_to?(:auto_incremented?) && column.auto_incremented?
      end

      def default_sequence_name(table_name, _primary_key)
        "#{table_name}_seq"
      end

      def prefetch_primary_key?(_table_name = nil)
        false
      end

      def next_sequence_value(_sequence_name)
        0
      end

      # ========== UTILITY METHODS ==========
      def case_sensitive_comparison(attribute, value)
        attribute.eq(value)
      end

      def case_insensitive_comparison(attribute, value)
        Arel::Nodes::NamedFunction.new("UPPER", [attribute]).eq(value.upcase)
      end

      def connection_alive?
        active?
      end

      def column_for(table_name, column_name)
        columns(table_name).find { |col| col.name == column_name.to_s }
      end

      def build_insert_sql(insert)
        sql = "INSERT INTO #{quote_table_name(insert.into)} "

        if insert.values_list && insert.values_list.any?
          columns = insert.values_list.first.keys
          sql << "(#{columns.map { |col| quote_column_name(col) }.join(", ")}) "
          sql << "VALUES "

          values = insert.values_list.map do |row|
            "(#{columns.map { |col| quote(row[col]) }.join(", ")}) "
          end.join(", ")

          sql << values
        else
          sql << "DEFAULT VALUES "
        end

        if insert.returns && !insert.returns.empty?
          sql << " RETURNING #{insert.returns.map { |col| quote_column_name(col) }.join(", ")}"
        end

        sql
      end

      def create_table_definition(name, **options)
        Firebird::TableDefinition.new(self, name, **options)
      end

      def create_alter_table(name)
        Firebird::AlterTable.new(create_table_definition(name))
      end

      def schema_creation
        Firebird::SchemaCreation.new(self)
      end

      def add_index_options(table_name, column_name, **options)
        column_names = Array(column_name)
        index_name = options[:name] || index_name(table_name, column_names)

        index_type = options[:unique] ? "UNIQUE " : ""
        index_columns = column_names.map { |col| quote_column_name(col) }.join(", ")

        [index_name, index_type, index_columns, options]
      end

      def index_name(table_name, options)
        case options
        when Hash
          if options[:column]
            columns = Array(options[:column])
            "index_#{table_name}_on_#{columns.join("_and_")}"
          else
            options[:name]
          end
        else
          columns = Array(options)
          "index_#{table_name}_on_#{columns.join("_and_")}"
        end
      end

      def index_name_for_remove(table_name, column_name = nil, options = {})
        return options[:name] if options.key?(:name)
        raise ArgumentError, "No name or column specified" unless column_name

        index_name(table_name, column: column_name)
      end

      def check_constraint_name(table_name, **options)
        options.fetch(:name) do
          expression = options.fetch(:expression) { options[:check] }
          identifier = Digest::SHA256.hexdigest(expression).first(10)
          "chk_#{table_name}_#{identifier}"
        end
      end

      def lookup_cast_type_from_column(column)
        lookup_cast_type(column.sql_type)
      end

      def query_value(sql, name = nil, allow_retry: false)
        select_value(sql, name, allow_retry: allow_retry)
      end

      def select_value(sql, name = nil, allow_retry: false)
        result = select_all(sql, name)
        return nil unless result.respond_to?(:rows) && result.rows.any? && result.rows.first&.any?

        unwrap_value(result.rows.first.first)
      end

      def query_values(sql, name = nil)
        select_values(sql, name)
      end

      def query(sql, name = nil)
        result = select_all(sql, name)
        result.rows
      end

      def current_savepoint_name
        "active_record_#{object_id}"
      end

      def type_to_sql(type, limit: nil, precision: nil, scale: nil, **)
        case type.to_s
        when "integer"
          case limit
          when 1, 2 then "SMALLINT"
          when 3, 4, nil then "INTEGER"
          when 5..8 then "BIGINT"
          else raise ArgumentError, "No integer type has byte size #{limit}"
          end
        when "string"
          "VARCHAR(#{limit || 255})"
        when "text"
          "BLOB SUB_TYPE TEXT"
        when "binary"
          "BLOB SUB_TYPE BINARY"
        when "boolean"
          "BOOLEAN"
        when "decfloat"
          "DECFLOAT"
        when "time"
          "TIME"
        when "datetime", "timestamp"
          "TIMESTAMP"
        when "time_with_timezone"
          "TIME WITH TIME ZONE"
        when "timestamp_with_timezone"
          "TIMESTAMP WITH TIME ZONE"
        when "float"
          "FLOAT"
        when "decimal", "numeric"
          if precision
            if scale
              "NUMERIC(#{precision},#{scale})"
            else
              "NUMERIC(#{precision})"
            end
          else
            "NUMERIC"
          end
        when "date"
          "DATE"
        when "bigint"
          "BIGINT"
        when "int128"
          supports_int128? ? "INT128" : "BIGINT"
        when "timestamptz"
          supports_time_zones? ? "TIMESTAMP WITH TIME ZONE" : "TIMESTAMP"
        when "timetz"
          supports_time_zones? ? "TIME WITH TIME ZONE" : "TIME"
        else
          super
        end
      end

      def extract_value_from_default(default)
        return nil if default.nil?

        case default
        when /^DEFAULT\s+'(.*)'/m
          value = Regexp.last_match(1).gsub("''", "'")
          case value.upcase
          when "TRUE" then true
          when "FALSE" then false
          else value
          end
        when /^DEFAULT\s+(.*)/m
          value = Regexp.last_match(1)
          case value.upcase
          when "TRUE" then true
          when "FALSE" then false
          else value
          end
        else
          default
        end
      end

      private

      def unwrap_value(value)
        value = value.first while value.is_a?(Array) && value.length == 1
        value
      end

      def translate_exception(exception, message:, sql:, binds:)
        case exception
        when ::Fb::Error
          case exception.message
          when /violation of PRIMARY/ then RecordNotUnique.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when /violation of FOREIGN KEY/ then InvalidForeignKey.new(message, sql: sql, binds: binds,
                                                                              connection_pool: @pool)
          when /CHECK constraint/ then StatementInvalid.new(message, sql: sql, binds: binds, connection_pool: @pool)
          when /lock conflict/ then LockWaitTimeout.new(message, sql: sql, binds: binds, connection_pool: @pool)
          else StatementInvalid.new(message, sql: sql, binds: binds, connection_pool: @pool)
          end
        else
          super
        end
      end

      def initialize_type_map(m = type_map)
        super
        register_class_with_limit m, /varchar/i, Type::String
        register_class_with_limit m, /char/i, Type::String
        register_class_with_precision m, /numeric/i, Type::Decimal
        register_class_with_precision m, /decimal/i, Type::Decimal

        m.register_type "boolean", Type::Boolean.new
        m.register_type "blob sub_type text", Type::Text.new
        m.register_type "blob sub_type binary", Type::Binary.new
        m.register_type "timestamp", Type::DateTime.new
        m.register_type "timestamp with time zone", Type::DateTime.new if supports_time_zones?
        m.register_type "date", Type::Date.new
        m.register_type "time", Type::Time.new
        m.register_type "time with time zone", Type::Time.new if supports_time_zones?
        m.register_type "smallint", Type::Integer.new(limit: 2)
        m.register_type "integer", Type::Integer.new(limit: 4)
        m.register_type "bigint", Type::BigInteger.new(limit: 8)
        m.register_type "int128", Type::BigInteger.new if supports_int128?
        m.register_type "float", Type::Float.new
        m.register_type "double precision", Type::Float.new
        m.register_type "numeric", Type::Decimal.new
        m.register_type "decimal", Type::Decimal.new
      end
    end
  end
end
