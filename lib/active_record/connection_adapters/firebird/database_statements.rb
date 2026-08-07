# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      module DatabaseStatements
        def internal_execute(sql, name = "SQL", binds = [], prepare: false, async: false, allow_retry: false, materialize_transactions: true, &block)
          connect unless active?
          materialize_transactions if materialize_transactions
          casted_binds = type_casted_binds(binds)
          log(sql, name, binds) do
            ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
              @connection.execute(sql, *casted_binds)
            end
          end
        rescue => e
          raise translate_exception_class(e, sql, binds)
        end

        def internal_exec_query(sql, name = "SQL", binds = [], prepare: false, async: false, allow_retry: false, materialize_transactions: true)
          cursor = internal_execute(sql, name, binds, prepare: prepare, async: async, allow_retry: allow_retry, materialize_transactions: materialize_transactions)

          if cursor.is_a?(Fb::Cursor)
            columns = cursor.fields.map { |f| f.name.downcase }
            rows = cursor.fetchall
            cursor.close
            ActiveRecord::Result.new(columns, rows)
          elsif cursor.is_a?(Hash)
            if cursor.key?(:returning) || sql.upcase.include?("RETURNING")
              columns = ["id"]
              rows = [cursor[:returning]]
              ActiveRecord::Result.new(columns, rows)
            elsif cursor.key?(:rows_affected)
              result = ActiveRecord::Result.new([], [])
              result.instance_variable_set(:@rows_affected, cursor[:rows_affected] || 0)
              result
            else
              ActiveRecord::Result.new([], [])
            end
          elsif cursor.is_a?(Integer)
            result = ActiveRecord::Result.new([], [])
            result.instance_variable_set(:@rows_affected, cursor)
            result
          else
            ActiveRecord::Result.new([], [])
          end
        end

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

        def exec_rollback_to_savepoint(name = current_savepoint_name)
          rollback_to_savepoint(name)
        end

        def release_savepoint(name = current_savepoint_name)
          return unless transaction_open?

          log("RELEASE SAVEPOINT #{name}", "TRANSACTION") do
            execute("RELEASE SAVEPOINT #{name}")
          end
        end

        def type_casted_binds(binds)
          binds.map do |value|
            if value.is_a?(ActiveModel::Attribute)
              type_cast(value.value_for_database)
            else
              type_cast(value)
            end
          end
        end

        def exec_update(sql, name = nil, binds = [])
          result = internal_exec_query(sql, name, binds)
          result.instance_variable_get(:@rows_affected) || 0
        end

        def exec_delete(sql, name = nil, binds = [])
          result = internal_exec_query(sql, name, binds)
          result.instance_variable_get(:@rows_affected) || 0
        end

        def raw_execute(sql, _name = nil, binds = [], prepare: false, async: false, **_options)
          connect unless active?

          if binds.any?
            @connection.execute(sql, *binds)
          else
            @connection.execute(sql)
          end
        end

        # ---------- BULK INSERTS ----------

        # Rails 8.1 builds bulk INSERTs via this hook. Firebird does not
        # support multi-row VALUES lists, so rows are rewritten as
        # "SELECT ... FROM RDB$DATABASE UNION ALL ...", and duplicate
        # handling is implemented with MERGE instead of ON CONFLICT.
        def build_insert_sql(insert)
          if insert.skip_duplicates?
            if merge_match_columns_present?(insert)
              build_merge_insert_sql(insert, update_on_conflict: false)
            else
              build_plain_insert_sql(insert)
            end
          elsif insert.update_duplicates?
            build_merge_insert_sql(insert, update_on_conflict: true)
          else
            build_plain_insert_sql(insert)
          end
        end

        def build_plain_insert_sql(insert)
          values_list = insert.values_list
          single_row = split_values_rows(values_list.sub(/\AVALUES\s+/i, "")).size <= 1
          sql = +"INSERT #{insert.into} #{values_to_select(values_list)}"
          sql << " RETURNING #{insert.returning}" if single_row && insert.returning
          sql
        end

        private

        def build_merge_insert_sql(insert, update_on_conflict:)
          table, columns = insert_table_and_columns(insert)
          source = values_to_select(insert.values_list, columns)
          # Matching can only reference columns present in the inserted values.
          # An identity PK (or any column absent from the values) is not in the
          # source, so it cannot drive the MERGE conflict.
          match_columns = insert_match_columns(insert) & columns

          if match_columns.empty?
            raise ArgumentError,
                  "#{self.class} requires the conflict/unique columns to be present in the inserted values for MERGE. " \
                  "Pass :unique_by (or include the primary key in the attributes)."
          end

          on_condition = match_columns.map { |c| "t.#{c} = src.#{c}" }.join(" AND ")
          insert_columns = columns.join(", ")
          insert_values = columns.map { |c| "src.#{c}" }.join(", ")

          sql = +"MERGE INTO #{table} t USING (#{source}) src ON (#{on_condition})"

          if update_on_conflict
            if insert.raw_update_sql?
              sql << " WHEN MATCHED THEN UPDATE SET #{insert.raw_update_sql}"
            else
              updates = +""
              updates << insert.touch_model_timestamps_unless { |col| "t.#{col} = src.#{col}" }
              updates << insert.updatable_columns.map { |col| "t.#{col} = src.#{col}" }.join(",")
              sql << " WHEN MATCHED THEN UPDATE SET #{updates}" unless updates.empty?
            end
          end

          sql << " WHEN NOT MATCHED THEN INSERT (#{insert_columns}) VALUES (#{insert_values})"
          sql
        end

        def insert_table_and_columns(insert)
          into = insert.into # e.g. 'INTO "TABLE" (A,B)'
          match = into.match(/\AINTO\s+(.+?)\s+\((.*)\)\z/m)
          table = match[1]
          columns = match[2].split(",").map(&:strip)
          [table, columns]
        end

        def insert_match_columns(insert)
          if (target = insert.conflict_target)
            if (m = target.match(/\(([^)]+)\)/))
              m[1].split(",").map(&:strip)
            else
              []
            end
          else
            insert.primary_keys.map { |pk| quote_column_name(pk) }
          end
        end

        def merge_match_columns_present?(insert)
          table, columns = insert_table_and_columns(insert)
          (insert_match_columns(insert) & columns).any?
        end

        # Converts "(a, b), (c, d)" into
        # "SELECT a AS X, b AS Y FROM RDB$DATABASE UNION ALL SELECT c, d FROM RDB$DATABASE"
        def values_to_select(values_list, columns = nil)
          values_list = values_list.sub(/\AVALUES\s+/i, "")
          rows = split_values_rows(values_list)
          selects = rows.map do |row|
            values = split_commas(row)
            if columns
              aliased = columns.zip(values).map { |c, v| "#{v} AS #{c}" }.join(", ")
              "SELECT #{aliased} FROM RDB$DATABASE"
            else
              "SELECT #{values.join(", ")} FROM RDB$DATABASE"
            end
          end
          selects.join(" UNION ALL ")
        end

        # Splits "(v1, v2), (v3, v4)" into ["v1, v2", "v3, v4"]
        def split_values_rows(values_list)
          rows = []
          current = +""
          depth = 0
          in_string = false

          str = values_list
          i = 0
          while i < str.length
            ch = str[i]

            if in_string
              current << ch
              if ch == "'"
                if str[i + 1] == "'"
                  current << str[i + 1]
                  i += 1
                else
                  in_string = false
                end
              end
            else
              case ch
              when "'" then in_string = true; current << ch
              when "(" then depth += 1; current << ch
              when ")"
                depth -= 1
                current << ch
              when ","
                if depth == 0
                  rows << current.strip
                  current = +""
                else
                  current << ch
                end
              else
                current << ch
              end
            end
            i += 1
          end
          rows << current.strip unless current.strip.empty?
          rows.map { |r| r.sub(/\A\(/, "").sub(/\)\z/, "").strip }
        end

        def split_commas(str)
          parts = []
          current = +""
          depth = 0
          in_string = false

          i = 0
          while i < str.length
            ch = str[i]

            if in_string
              current << ch
              if ch == "'"
                if str[i + 1] == "'"
                  current << str[i + 1]
                  i += 1
                else
                  in_string = false
                end
              end
            else
              case ch
              when "'" then in_string = true; current << ch
              when "(" then depth += 1; current << ch
              when ")"
                depth -= 1
                current << ch
              when ","
                if depth == 0
                  parts << current.strip
                  current = +""
                else
                  current << ch
                end
              else
                current << ch
              end
            end
            i += 1
          end
          parts << current.strip unless current.strip.empty?
          parts
        end
      end
    end
  end
end