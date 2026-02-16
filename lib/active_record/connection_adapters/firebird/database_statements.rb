# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      module DatabaseStatements
        def internal_exec_query(sql, name = "SQL", binds = [], prepare: false, async: false, allow_retry: false)
          log(sql, name, binds, async: async) do
            # Extract limit/offset values from binds if using parameterized LIMIT/OFFSET
            limit_value = nil
            offset_value = nil

            if binds.is_a?(Array) && !binds.empty?
              sql_str = sql.respond_to?(:to_sql) ? sql.to_sql : sql.to_s

              # Check what bind parameters we have
              has_limit = sql_str.include?("LIMIT")
              has_offset = sql_str.include?("OFFSET")

              binds = binds.dup

              if has_limit && has_offset
                # Both LIMIT and OFFSET - OFFSET is first in binds, then LIMIT
                offset_value = extract_bind_value(binds.pop) if has_offset
                limit_value = extract_bind_value(binds.pop) if has_limit
              elsif has_offset
                offset_value = extract_bind_value(binds.pop)
              elsif has_limit
                limit_value = extract_bind_value(binds.pop)
              end
            end

            # Convert LIMIT to FIRST/SKIP syntax for Firebird
            sql = convert_limit_to_first_skip(sql, limit_value, offset_value)

            puts "DEBUG: Executing SQL: #{sql}" if ENV["DEBUG_SQL"]

            if sql.match?(/\A\s*SELECT\b/i)
              result = raw_query(sql, *type_casted_binds(binds))
              build_result(result)
            else
              affected_rows = raw_execute(sql, *type_casted_binds(binds))
              result = ActiveRecord::Result.new([], [])
              result.define_singleton_method(:rows_affected) { affected_rows || 0 }
              result
            end
          end
        rescue ::Fb::Error => e
          raise translate_exception(e, message: "#{e.class.name}: #{e.message}", sql: sql, binds: binds)
        end

        def extract_bind_value(bind)
          return nil unless bind

          if bind.respond_to?(:value)
            bind.value
          elsif bind.respond_to?(:value_for_database)
            bind.value_for_database
          else
            bind
          end
        end

        def select_all(arel, _name = nil, binds = [], preparable: nil, async: false, allow_retry: false)
          # In AR 7.2, binds are stored on the Arel AST, not passed as a separate parameter
          # We need to use the visitor to compile the SQL and get the binds
          arel = arel_from_relation(arel)

          # If arel is still a String, use it directly
          if arel.is_a?(String)
            sql = arel
            extracted_binds = binds
          else
            # Compile using the visitor to get SQL and binds
            collector = collector()
            collector.retryable = true

            if prepared_statements && preparable
              collector.preparable = true
              result = visitor.compile(arel, collector)
              if result.is_a?(Array)
                sql = result[0]
                extracted_binds = result[1] || []
              else
                sql = result
                extracted_binds = []
              end
            else
              result = visitor.compile(arel, collector)
              if result.is_a?(Array)
                sql = result[0]
                extracted_binds = result[1] || []
              else
                sql = result
                extracted_binds = []
              end
            end

            # Clean up SQL - remove extra parentheses that visitor might add
            sql = sql.gsub(/^\s*\(\s*SELECT/i, "SELECT").gsub(/\)\s*$/, "").strip
          end

          # Extract limit/offset from Arel if available (for non-prepared statements)
          limit_value = nil
          offset_value = nil

          if arel.respond_to?(:limit) && arel.limit
            limit_node = arel.limit
            limit_value = limit_node.respond_to?(:value) ? limit_node.value : limit_node
          end
          if arel.respond_to?(:offset) && arel.offset
            offset_node = arel.offset
            offset_value = offset_node.respond_to?(:value) ? offset_node.value : offset_node
          end

          # Try to extract LIMIT bind from binds array and remove it
          if extracted_binds.is_a?(Array) && !extracted_binds.empty?
            if ENV["DEBUG_SQL"]
              puts "DEBUG: Looking for LIMIT in binds: #{extracted_binds.map do |b|
                b.respond_to?(:name) ? b.name : b.class
              end.inspect}"
            end
            # Look for a LIMIT bind in the binds array
            extracted_binds.each_with_index do |bind, idx|
              bind_name = bind.respond_to?(:name) ? bind.name : nil
              if ENV["DEBUG_SQL"]
                puts "DEBUG: Checking bind #{idx}: #{bind_name}, match: #{bind_name.to_s.upcase == "LIMIT"}"
              end
              next unless bind_name && bind_name.to_s.upcase == "LIMIT"

              limit_value ||= bind.respond_to?(:value) ? bind.value : bind
              extracted_binds = extracted_binds.dup
              extracted_binds.delete_at(idx)
              puts "DEBUG: Removed LIMIT bind from binds" if ENV["DEBUG_SQL"]
              break
            end
          end

          # Convert LIMIT to FIRST/SKIP for Firebird
          sql = convert_limit_to_first_skip(sql, limit_value, offset_value)

          puts "DEBUG: select_all sql=#{sql.inspect[0..80]}, binds=#{extracted_binds.inspect}" if ENV["DEBUG_SQL"]

          # Convert bind attributes to values for the Fb gem
          bind_values = extracted_binds.map do |bind|
            if bind.respond_to?(:value_for_database)
              bind.value_for_database
            elsif bind.respond_to?(:value)
              bind.value
            else
              bind
            end
          end

          puts "DEBUG: bind_values=#{bind_values.inspect}" if ENV["DEBUG_SQL"]

          result = raw_query(sql, *bind_values)

          # Convert raw result to ActiveRecord::Result
          if result.is_a?(Array)
            if result.empty?
              ar_result = ActiveRecord::Result.new([], [])
            elsif result.first.is_a?(Array)
              # Result is array of arrays - need to generate column names
              columns = generate_column_names_from_sql(sql)
              puts "DEBUG: result columns from generate_column_names_from_sql: #{columns.inspect}" if ENV["DEBUG_SQL"]
              rows = result.map { |row| row.map { |val| val&.respond_to?(:rstrip) ? val.rstrip : val } }
              ar_result = ActiveRecord::Result.new(columns, rows)
            elsif result.first.is_a?(Hash)
              columns = result.first.keys
              rows = result.map { |row| columns.map { |col| row[col] } }
              ar_result = ActiveRecord::Result.new(columns, rows)
            else
              ar_result = ActiveRecord::Result.new(["value"], result.map { |v| [v] })
            end
            puts "DEBUG: ActiveRecord::Result columns: #{ar_result.columns.inspect}" if ENV["DEBUG_SQL"]
            ar_result
          else
            result
          end
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
          result = internal_exec_query(sql, name, binds)
          result.rows_affected || 0
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

        def convert_limit_to_first_skip(sql, limit_value = nil, offset_value = nil)
          sql_str = sql.respond_to?(:to_sql) ? sql.to_sql : sql.to_s
          return sql_str unless sql_str.match?(/LIMIT|OFFSET/i)

          new_sql = sql_str.dup

          # Handle both LIMIT and OFFSET together in one pass
          limit_pattern = /\bLIMIT\s+(\?|\d+)(?:\s+OFFSET\s+(\?|\d+))?/i
          offset_pattern = /\bOFFSET\s+(\?|\d+)/i

          has_limit = sql_str.match?(/\bLIMIT\b/i)
          has_offset = sql_str.match?(/\bOFFSET\b/i)

          if has_limit && match = sql_str.match(limit_pattern)
            limit = match[1]
            offset = match[2]

            # If placeholders, replace with actual values from binds
            if limit == "?" && limit_value
              limit = limit_value.respond_to?(:value) ? limit_value.value : limit_value
              limit = limit.to_i if limit.respond_to?(:to_i)
            end
            if offset == "?" && offset_value
              offset = offset_value.respond_to?(:value) ? offset_value.value : offset_value
              offset = offset.to_i if offset.respond_to?(:to_i)
            end

            offset ||= 0

            # Remove both LIMIT and OFFSET clauses
            new_sql.gsub!(limit_pattern, "")
            new_sql.gsub!(offset_pattern, "") if has_offset && !match[2]

            # Add FIRST/SKIP at the beginning of SELECT
            if offset.to_i > 0
              new_sql.sub!(/\bSELECT\b/i) { "SELECT FIRST #{limit} SKIP #{offset}" }
            else
              new_sql.sub!(/\bSELECT\b/i) { "SELECT FIRST #{limit}" }
            end
          elsif has_offset && match = sql_str.match(offset_pattern)
            offset = match[1]

            # If placeholder, replace with actual value
            if offset == "?" && offset_value
              offset = offset_value.respond_to?(:value) ? offset_value.value : offset_value
              offset = offset.to_i if offset.respond_to?(:to_i)
            end

            # Remove OFFSET clause
            new_sql.gsub!(offset_pattern, "")

            # Add SKIP at the beginning of SELECT
            new_sql.sub!(/\bSELECT\b/i) { "SELECT SKIP #{offset}" }
          end

          new_sql
        end

        def generate_column_names_from_sql(sql)
          sql_str = sql.respond_to?(:to_sql) ? sql.to_sql : sql.to_s
          puts "DEBUG generate_column_names_from_sql: sql_str=#{sql_str.inspect[0..100]}" if ENV["DEBUG_SQL"]

          return ["count"] if sql_str.match?(/COUNT\s*\(\s*\*\s*\)/i)
          return ["value"] if sql_str.match?(/SELECT\s+\d+\s+FROM/i) && !sql_str.match?(/FIRST/i)

          select_match = sql_str.match(/SELECT\s+(.+?)\s+FROM\s+/i)
          if select_match
            select_clause = select_match[1].strip
            # Remove FIRST n [SKIP m] from the select clause
            select_clause.gsub!(/FIRST\s+\d+\s+SKIP\s+\d+\s*/i, "")
            select_clause.gsub!(/FIRST\s+\d+\s*/i, "")

            columns = select_clause.split(",").map do |col|
              col = col.strip
              # Handle table.* case - we need to get columns from schema
              if col.include?(".*")
                # Extract table name and try to get columns from schema
                table_name = col.sub(".*", "").split(".").last
                # Remove quotes from table name
                table_name = table_name.delete('"')
                begin
                  # Try both quoted and unquoted versions
                  cols = begin
                    schema_cache.columns_hash(table_name)
                  rescue StandardError
                    nil
                  end
                  cols ||= begin
                    schema_cache.columns_hash(table_name.downcase)
                  rescue StandardError
                    nil
                  end
                  cols ||= begin
                    schema_cache.columns_hash(table_name.upcase)
                  rescue StandardError
                    nil
                  end
                  return cols ? cols.keys : ["id"]
                rescue StandardError => e
                  puts "DEBUG: Error getting columns: #{e.message}" if ENV["DEBUG_SQL"]
                  return ["id"]
                end
              else
                # Remove table prefix but keep the column name
                col.gsub!(/\w+\./, "")
                col.gsub!(/\w+\s*\([^)]*\)/, "value")
                col.gsub!(/\s+AS\s+\w+/i, "")
                col.gsub!(/[^a-zA-Z0-9_]/, "_")
                col.downcase
              end
            end
            columns.reject(&:empty?).presence || ["column"]
          else
            ["column"]
          end
        end
      end
    end
  end
end
