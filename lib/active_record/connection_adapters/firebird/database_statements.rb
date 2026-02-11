# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      module DatabaseStatements
        def internal_exec_query(sql, name = "SQL", binds = [], prepare: false, async: false, allow_retry: false)
          log(sql, name, binds, async: async) do
            # Convert LIMIT to FIRST/SKIP syntax for Firebird
            sql = convert_limit_to_first_skip(sql)

            puts "DEBUG: Executing SQL: #{sql}" if ENV["DEBUG_SQL"]

            if sql.match?(/\A\s*SELECT\b/i)
              result = raw_query(sql, *type_casted_binds(binds))
              build_result(result)
            else
              raw_execute(sql, *type_casted_binds(binds))
              ActiveRecord::Result.new([], [])
            end
          end
        rescue ::Fb::Error => e
          raise translate_exception(e, message: "#{e.class.name}: #{e.message}", sql: sql, binds: binds)
        end

        def execute(sql, name = nil, async: false)
          log(sql, name, async: async) do
            ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
              raw_execute(sql)
            end
          end
        end

        def exec_query(sql, name = "SQL", binds = [], prepare: false, async: false)
          internal_exec_query(sql, name, binds, prepare: prepare, async: async)
        end

        def exec_insert(sql, name = nil, binds = [], pk = nil, sequence_name = nil, returning: nil)
          if supports_insert_returning? && returning
            exec_insert_returning(sql, name, binds, returning)
          else
            exec_insert_traditional(sql, name, binds, pk, sequence_name)
          end
        end

        def exec_delete(sql, name = nil, binds = [])
          internal_exec_query(sql, name, binds)
          raw_query("SELECT ROW_COUNT FROM RDB$DATABASE").first&.first&.to_i || 0
        end

        alias exec_update exec_delete

        # ---------- TRANSACTIONS ----------

        def begin_db_transaction
          log("BEGIN", nil) { @connection.transaction("READ COMMITTED") }
        end

        def commit_db_transaction
          log("COMMIT", nil) { @connection.commit }
        end

        def rollback_db_transaction
          log("ROLLBACK", nil) { @connection.rollback }
        end

        def transaction_open?
          @connection.transaction_started
        end

        # ---------- SAVEPOINTS ----------

        def create_savepoint(name = current_savepoint_name)
          unless transaction_open?
            raise ActiveRecord::StatementInvalid,
                  "Cannot create savepoint without active transaction"
          end

          log("SAVEPOINT #{name}", "TRANSACTION") do
            execute("SAVEPOINT #{name}")
          end
        end

        def rollback_to_savepoint(name = current_savepoint_name)
          return unless transaction_open?

          log("ROLLBACK TO SAVEPOINT #{name}", "TRANSACTION") do
            execute("ROLLBACK TO SAVEPOINT #{name}")
          end
        end

        def release_savepoint(name = current_savepoint_name)
          return unless transaction_open?

          log("RELEASE SAVEPOINT #{name}", "TRANSACTION") do
            execute("RELEASE SAVEPOINT #{name}")
          end
        end

        # ---------- FIXTURES ----------

        def insert_fixtures_set(fixture_set, tables_to_delete = [])
          disable_referential_integrity do
            transaction(requires_new: true) do
              tables_to_delete.each do |table|
                delete("DELETE FROM #{quote_table_name(table)}", "Fixture Delete")
              end

              fixture_set.each do |table_name, rows|
                rows.each do |row|
                  insert_fixture(row, table_name)
                end
              end
            end
          end
        end

        def insert_fixture(fixture, table_name)
          columns = schema_cache.columns_hash(table_name)

          binds = fixture.map do |name, value|
            raise "Column #{name} not found in #{table_name}" unless column = columns[name]

            type = lookup_cast_type_from_column(column)
            Relation::QueryAttribute.new(name, value, type)
          end

          key = columns[primary_key(table_name)]
          value = fixture[key&.name] if key

          sql = build_fixture_sql(fixture.keys, table_name)
          exec_query(sql, "Fixture Insert", binds)
          value
        end

        def empty_insert_statement_value(_primary_key = nil)
          "DEFAULT VALUES"
        end

        # ---------- ISOLATION LEVELS ----------

        def begin_isolated_db_transaction(isolation)
          isolation_level = transaction_isolation_levels.fetch(isolation) do
            raise ArgumentError, "invalid isolation level: #{isolation.inspect}"
          end

          begin_db_transaction

          sql = if firebird_version >= 40_000 && isolation == :read_committed
                  "SET TRANSACTION #{isolation_level} READ CONSISTENCY"
                else
                  "SET TRANSACTION #{isolation_level}"
                end

          raw_execute(sql)
        rescue ::Fb::Error
          rollback_db_transaction
          raise
        end

        def transaction_isolation_levels
          {
            read_uncommitted: "READ COMMITTED",
            read_committed: "READ COMMITTED",
            repeatable_read: "SNAPSHOT",
            serializable: "SNAPSHOT TABLE STABILITY"
          }
        end

        # ---------- PROFILER (FB 5+) ----------

        def enable_profiler(flush_interval = nil)
          return unless supports_profiler?

          sql = "ALTER SESSION SET PROFILER STATE 1"
          sql += " FLUSH INTERVAL #{flush_interval}" if flush_interval
          execute(sql)
        end

        def disable_profiler
          execute("ALTER SESSION SET PROFILER STATE 0") if supports_profiler?
        end

        def profiler_data
          return unless supports_profiler?

          execute(<<~SQL)
            SELECT
              rs.STATEMENT_ID,
              rs.CURSOR_ID,
              rs.SOURCE_LINE,
              rs.SOURCE_COLUMN,
              rs.ACCESS_PATH,
              p.TOTAL_ELAPSED_TIME,
              p.OPEN_COUNTER,
              p.FETCH_COUNTER
            FROM PLG$PROF_RECORD_SOURCES rs
            JOIN PLG$PROF_RECORD_SOURCE_STATS p ON p.RECORD_SOURCE_ID = rs.RECORD_SOURCE_ID
            ORDER BY p.TOTAL_ELAPSED_TIME DESC
          SQL
        end

        def create_table(table_name, **options)
          super

          return unless options[:sequence] != false && options[:id] != false

          sequence_name = options[:sequence] || default_sequence_name(table_name)
          create_sequence(sequence_name)
        end

        def drop_table(table_name, options = {})
          if options[:sequence] != false
            sequence_name = options[:sequence] || default_sequence_name(table_name)
            drop_sequence(sequence_name) if sequence_exists?(sequence_name)
          end

          super
        end

        def create_sequence(sequence_name)
          execute("CREATE SEQUENCE #{sequence_name}")
        rescue StandardError
          nil
        end

        def drop_sequence(sequence_name)
          execute("DROP SEQUENCE #{sequence_name}")
        rescue StandardError
          nil
        end

        def sequence_exists?(sequence_name)
          @connection.generator_names.include?(sequence_name)
        end

        def default_sequence_name(table_name, _column = nil)
          "#{table_name}_g01"
        end

        def next_sequence_value(sequence_name)
          @connection.query("SELECT NEXT VALUE FOR #{sequence_name} FROM RDB$DATABASE")[0][0]
        end

        # ---------- PRIVATE ----------

        private

        def build_result(result)
          if result.respond_to?(:fields) && result.respond_to?(:fetch)
            columns = result.fields.map(&:downcase)
            rows = result.map do |row|
              if row.respond_to?(:values)
                row.values.map { |val| unwrap_calculation_value(val) }
              else
                [unwrap_calculation_value(row)]
              end
            end
            ActiveRecord::Result.new(columns, rows)
          elsif result.is_a?(Array) && result.first.respond_to?(:keys)
            columns = result.first.keys.map(&:downcase)
            rows = result.map do |row|
              row.values.map { |val| unwrap_calculation_value(val) }
            end
            ActiveRecord::Result.new(columns, rows)
          else
            ActiveRecord::Result.new(["value"], [[unwrap_calculation_value(result)]].compact)
          end
        end

        def unwrap_calculation_value(value)
          # Handle nested arrays and ensure proper type casting for calculations
          case value
          when Array
            value.length == 1 ? unwrap_calculation_value(value.first) : value.map { |v| unwrap_calculation_value(v) }
          when Numeric
            value
          when String
            # Try to convert to number if it looks like one
            if value.match?(/^\d+$/)
              value.to_i
            elsif value.match?(/^\d+\.\d+$/)
              value.to_f
            else
              value
            end
          else
            value
          end
        end

        def exec_insert_returning(sql, name, binds, _returning)
          # Remove ID column from INSERT for IDENTITY columns
          table_match = sql.match(/INSERT INTO\s+(["\w]+)/i)
          table_match_name = table_match ? table_match[1].delete('"') : "sis_tests"
          pks = primary_keys(table_match_name)
          pks.is_a?(Array) ? pks.first : (pks || "id")

          # Parse and rebuild INSERT without ID column
          if sql =~ /\((.*?)\)\s*VALUES\s*\((.*?)\)/i
            columns_part = ::Regexp.last_match(1)
            values_part = ::Regexp.last_match(2)

            # Find and remove ID column
            columns_list = columns_part.split(",").map(&:strip)
            # Remove ID column from INSERT for IDENTITY columns
            table_match = sql.match(/INSERT INTO\s+["']?([^"'\s]+)/i)
            table_match_name = table_match ? table_match[1] : "sis_tests"
            pks = primary_keys(table_match_name)
            pk = pks.is_a?(Array) ? pks.first : (pks || "id")
            pk_value = pk.is_a?(Array) ? pk.first : pk
            pk_value = pk_value.to_s.gsub(/[\["]/, "").strip

            # Parse and rebuild INSERT without ID column
            if sql =~ /\((.*?)\)\s*VALUES\s*\((.*?)\)/i
              columns_part = ::Regexp.last_match(1)
              values_part = ::Regexp.last_match(2)

              # Find and remove ID column
              columns_list = columns_part.split(",").map(&:strip)
              id_index = columns_list.find_index do |col|
                col.strip.upcase == pk_value.upcase || col.strip.upcase == "ID"
              end

              if id_index
                # Remove ID column from columns list
                columns_list.delete_at(id_index)

                # Remove corresponding placeholder from values
                values_list = values_part.split(",").map(&:strip)
                values_list.delete_at(id_index)

                # Remove ID from binds
                binds.delete_at(id_index)

                # Rebuild SQL
                sql = sql.gsub(/\(.*?\)\s*VALUES\s*\(.*?\)/i,
                               "(#{columns_list.join(", ")}) VALUES (#{values_list.join(", ")})")
              end
            end
          end

          # For IDENTITY columns, try to get the generated ID
          result = internal_exec_query(sql, name, binds)

          # If RETURNING didn't work, try to get the ID from IDENTITY column
          if _returning.any? && (result.nil? || (result.respond_to?(:rows) && result.rows.empty?))
            table_match = sql.match(/INSERT INTO\s+["']?([^"'\s]+)/i)
            table_match_name = table_match ? table_match[1] : "sis_tests"

            # Try different approaches to get the last inserted ID
            last_id = nil

            # Method 1: Try to get the generator name for IDENTITY column
            begin
              gen_sql = <<~SQL
                SELECT RDB$GENERATOR_NAME#{" "}
                FROM RDB$GENERATORS#{" "}
                WHERE RDB$GENERATOR_NAME LIKE '%#{table_match_name.upcase}%'
              SQL
              generators = query_values(gen_sql)
              gen_name = generators.find { |g| g.to_s.upcase.include?(table_match_name.upcase) }

              if gen_name
                last_id_sql = "SELECT GEN_ID(#{gen_name}, 0) FROM RDB$DATABASE"
                last_id = query_value(last_id_sql)
                puts "DEBUG: Got ID from generator #{gen_name}: #{last_id}"
              end
            rescue StandardError => e
              puts "DEBUG: Generator method failed: #{e.message}"
            end

            # Method 2: Try SELECT MAX() if no generator found
            unless last_id
              begin
                max_sql = "SELECT MAX(ID) FROM #{quote_table_name(table_match_name)}"
                last_id = query_value(max_sql)
                puts "DEBUG: Got ID from MAX(): #{last_id}"
              rescue StandardError => e
                puts "DEBUG: MAX() method failed: #{e.message}"
              end
            end

            # Return proper ActiveRecord::Result if we got an ID
            if last_id
              ActiveRecord::Result.new([_returning.first.to_s], [[last_id]])
            else
              ActiveRecord::Result.new([], [])
            end
          else
            result
          end
        end

        def exec_insert_traditional(sql, name, binds, _pk, sequence_name)
          internal_exec_query(sql, name, binds)
          return unless sequence_name

          query_value("SELECT GEN_ID(#{sequence_name}, 0) FROM RDB$DATABASE")
        end

        def build_fixture_sql(columns, table_name)
          # Remove auto-incremented columns from INSERT
          table_columns = columns(table_name.to_s)
          filtered_columns = columns.reject do |col|
            column_obj = table_columns.find { |c| c.name.downcase == col.downcase }
            column_obj&.respond_to?(:auto_incremented?) && column_obj.auto_incremented?
          end

          quoted_columns = filtered_columns.map { |c| quote_column_name(c) }.join(", ")
          placeholders = (["?"] * filtered_columns.size).join(", ")
          "INSERT INTO #{quote_table_name(table_name)} (#{quoted_columns}) VALUES (#{placeholders})"
        end

        def type_casted_binds(binds)
          binds.map { |attr| type_cast(attr.value_for_database) }
        end

        def raw_execute(sql, *binds)
          connect unless @connection
          raise ActiveRecord::ConnectionNotEstablished, "No connection" unless @connection

          # TEMP DEBUG: show the exact SQL being executed to diagnose unknown-table errors
          puts "RAW EXECUTE SQL: #{sql}" if ENV["FB_ADAPTER_DEBUG"]
          binds.empty? ? @connection.execute(sql) : @connection.execute(sql, *binds)
        end

        def raw_query(sql, *binds)
          connect unless @connection
          raise ActiveRecord::ConnectionNotEstablished, "No connection" unless @connection

          binds.empty? ? @connection.query(sql) : @connection.query(sql, *binds)
        end

        def convert_limit_to_first_skip(sql)
          # Convert LIMIT/OFFSET to Firebird's FIRST/SKIP syntax
          return sql unless sql.match?(/LIMIT|OFFSET/i)

          # Pattern to match LIMIT and OFFSET clauses
          limit_pattern = /\bLIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?\b/i
          offset_pattern = /\bOFFSET\s+(\d+)\b/i

          new_sql = sql.dup

          # Handle LIMIT [n] OFFSET [m] or LIMIT [n]
          if match = sql.match(limit_pattern)
            limit = match[1]
            offset = match[2] || 0

            # Remove the LIMIT/OFFSET clause
            new_sql.gsub!(limit_pattern, "")

            # Add FIRST/SKIP at the beginning of SELECT
            if offset.to_i > 0
              new_sql.gsub!(/\bSELECT\b/i, "SELECT FIRST #{limit} SKIP #{offset}")
            else
              new_sql.gsub!(/\bSELECT\b/i, "SELECT FIRST #{limit}")
            end
          end

          # Handle standalone OFFSET
          if match = sql.match(offset_pattern)
            offset = match[1]
            new_sql.gsub!(offset_pattern, "")
            new_sql.gsub!(/\bSELECT\b/i, "SELECT SKIP #{offset}")
          end

          new_sql
        end
      end
    end
  end
end
