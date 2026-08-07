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
      end
    end
  end
end