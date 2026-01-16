# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Firebird Connection" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "basic connection" do
    it "connects to the database" do
      expect(connection).to be_active
    end

    it "has correct adapter name" do
      expect(connection.adapter_name).to eq("Firebird")
    end

    it "detects Firebird version" do
      version = connection.firebird_version
      expect(version).to be >= 30_000 # Al menos Firebird 3.0
      puts "Firebird version: #{version}" if ENV["DEBUG_SQL"]
    end

    it "can execute a simple query" do
      result = connection.select_value("SELECT 1 FROM RDB$DATABASE")
      expect(result).to eq(1)
    end

    it "can get current user" do
      user = connection.query_value("SELECT CURRENT_USER FROM RDB$DATABASE")
      expect(user.to_s.strip.upcase).to eq("SYSDBA")
    end
  end

  describe "connection lifecycle" do
    it "can reconnect" do
      expect { connection.reconnect! }.not_to raise_error
      expect(connection).to be_active
    end

    it "can disconnect" do
      connection.disconnect
      expect(connection).not_to be_active
      # Reconectar para no afectar otros tests
      connection.reconnect!
    end
  end

  describe "capabilities" do
    it "supports migrations" do
      expect(connection.supports_migrations?).to be true
    end

    it "supports foreign keys" do
      expect(connection.supports_foreign_keys?).to be true
    end

    it "supports savepoints" do
      expect(connection.supports_savepoints?).to be true
    end

    it "supports common table expressions" do
      expect(connection.supports_common_table_expressions?).to be true
    end

    it "supports window functions" do
      expect(connection.supports_window_functions?).to be true
    end

    it "supports insert returning" do
      expect(connection.supports_insert_returning?).to be true
    end

    context "version-specific features" do
      it "checks time zone support (Firebird 4+)" do
        if connection.firebird_version >= 40_000
          expect(connection.supports_time_zones?).to be true
        else
          expect(connection.supports_time_zones?).to be false
        end
      end

      it "checks SKIP LOCKED support (Firebird 5+)" do
        if connection.firebird_version >= 50_000
          expect(connection.supports_skip_locked?).to be true
        else
          expect(connection.supports_skip_locked?).to be false
        end
      end

      it "checks partial index support (Firebird 5+)" do
        if connection.firebird_version >= 50_000
          expect(connection.supports_partial_index?).to be true
        else
          expect(connection.supports_partial_index?).to be false
        end
      end

      it "checks INT128 support (Firebird 4+)" do
        if connection.firebird_version >= 40_000
          expect(connection.supports_int128?).to be true
        else
          expect(connection.supports_int128?).to be false
        end
      end
    end
  end

  describe "native database types" do
    it "has defined native types" do
      types = connection.native_database_types

      expect(types[:string]).to eq({ name: "VARCHAR", limit: 255 })
      expect(types[:text]).to eq({ name: "BLOB SUB_TYPE TEXT" })
      expect(types[:integer]).to eq({ name: "INTEGER" })
      expect(types[:bigint]).to eq({ name: "BIGINT" })
      expect(types[:float]).to eq({ name: "FLOAT" })
      expect(types[:decimal]).to eq({ name: "DECIMAL" })
      expect(types[:datetime]).to eq({ name: "TIMESTAMP" })
      expect(types[:date]).to eq({ name: "DATE" })
      expect(types[:time]).to eq({ name: "TIME" })
      expect(types[:boolean]).to eq({ name: "BOOLEAN" })
      expect(types[:binary]).to eq({ name: "BLOB SUB_TYPE BINARY" })
    end
  end

  describe "quoting" do
    it "quotes strings correctly" do
      quoted = connection.quote("O'Reilly")
      expect(quoted).to eq("'O''Reilly'")
    end

    it "quotes true as TRUE" do
      expect(connection.quoted_true).to eq("TRUE")
    end

    it "quotes false as FALSE" do
      expect(connection.quoted_false).to eq("FALSE")
    end

    it "quotes dates correctly" do
      date = Date.new(2024, 1, 15)
      quoted = connection.quote(date)
      expect(quoted).to match(/2024-01-15/)
    end

    it "quotes column names with case sensitivity" do
      # Nombres en mayúsculas no necesitan comillas
      expect(connection.quote_column_name("ID")).to eq("ID")
      expect(connection.quote_column_name("NAME")).to eq("NAME")

      # Nombres con minúsculas o caracteres especiales necesitan comillas
      expect(connection.quote_column_name("fieldName")).to eq('"fieldName"')
      expect(connection.quote_column_name("field name")).to eq('"field name"')
    end

    it "quotes table names correctly" do
      expect(connection.quote_table_name("users")).to eq('"users"')
      expect(connection.quote_table_name("USERS")).to eq("USERS")
    end
  end

  describe "transactions" do
    it "can begin and commit a transaction" do
      expect do
        connection.transaction do
          connection.execute("SELECT 1 FROM RDB$DATABASE")
        end
      end.not_to raise_error
    end

    it "debugs transaction behavior" do
      # Limpiar tabla primero
      connection.execute("DELETE FROM sis_tests")

      puts "=" * 50
      puts "DEBUGGING TRANSACTION BEHAVIOR"
      puts "=" * 50

      # Transacción 1 - commit (sin rollback)
      ActiveRecord::Base.transaction do
        puts "Transaction 1 - COMMIT test"
        connection.execute("INSERT INTO sis_tests (field_varchar) VALUES ('test_commit')")
        # NO hacemos rollback - debería committear
      end

      count_after_commit = connection.select_value("SELECT COUNT(*) FROM sis_tests WHERE field_varchar = 'test_commit'")
      puts "After commit: #{count_after_commit}"

      # Transacción 2 - rollback
      ActiveRecord::Base.transaction do
        puts "Transaction 2 - ROLLBACK test"
        connection.execute("INSERT INTO sis_tests (field_varchar) VALUES ('test_rollback')")

        # Verificar que se insertó dentro de la transacción
        count_inside = connection.select_value("SELECT COUNT(*) FROM sis_tests WHERE field_varchar = 'test_rollback'")
        puts "Count inside transaction before rollback: #{count_inside}"

        # Forzar rollback
        raise ActiveRecord::Rollback
      end

      count_after_rollback = connection.select_value("SELECT COUNT(*) FROM sis_tests WHERE field_varchar = 'test_rollback'")
      puts "After rollback: #{count_after_rollback}"

      # Resultados finales
      total_count = connection.select_value("SELECT COUNT(*) FROM sis_tests")
      puts "Total records in table: #{total_count}"

      # Expectations
      expect(count_after_commit).to eq(1), "Commit didn't work!"
      expect(count_after_rollback).to eq(0), "Rollback didn't work!"
      expect(total_count).to eq(1), "Expected only 1 record (from commit), but found #{total_count}"
    end

    it "supports savepoints" do
      # Asegurarnos de que la tabla está vacía
      connection.execute("DELETE FROM sis_tests")

      connection.transaction do
        connection.execute("INSERT INTO sis_tests (field_varchar) VALUES ('test1')")

        # Crear un savepoint - ahora funcionará porque estamos en una transacción activa
        connection.create_savepoint("test_savepoint")

        connection.execute("INSERT INTO sis_tests (field_varchar) VALUES ('test2')")

        # Verificar que ambos están presentes
        count_before_rollback = connection.select_value("SELECT COUNT(*) FROM sis_tests")
        puts "Count before rollback: #{count_before_rollback.inspect}" if ENV["DEBUG_SQL"]
        expect(count_before_rollback).to eq(2)

        # Revertir al savepoint (esto debería eliminar test2 pero mantener test1)
        connection.rollback_to_savepoint("test_savepoint")

        # Verificar dentro de la transacción
        count_test1_in_txn = connection.select_value("SELECT COUNT(*) FROM sis_tests WHERE field_varchar = 'test1'")
        count_test2_in_txn = connection.select_value("SELECT COUNT(*) FROM sis_tests WHERE field_varchar = 'test2'")

        puts "Count test1 in transaction: #{count_test1_in_txn.inspect}" if ENV["DEBUG_SQL"]
        puts "Count test2 in transaction: #{count_test2_in_txn.inspect}" if ENV["DEBUG_SQL"]

        expect(count_test1_in_txn).to eq(1)
        expect(count_test2_in_txn).to eq(0)
      end

      # Verificar después del commit
      count_test1 = connection.select_value("SELECT COUNT(*) FROM sis_tests WHERE field_varchar = 'test1'")
      count_test2 = connection.select_value("SELECT COUNT(*) FROM sis_tests WHERE field_varchar = 'test2'")

      puts "Final count test1: #{count_test1.inspect}" if ENV["DEBUG_SQL"]
      puts "Final count test2: #{count_test2.inspect}" if ENV["DEBUG_SQL"]

      expect(count_test1).to eq(1)
      expect(count_test2).to eq(0)
    end

    it "raises error when trying to create savepoint without active transaction" do
      # Intentar crear un savepoint sin transacción activa debe fallar
      expect do
        connection.create_savepoint("invalid_savepoint")
      end.to raise_error(ActiveRecord::StatementInvalid, /Cannot create savepoint without active transaction/)
    end

    # it "supports different isolation levels" do
    #   expect do
    #     # Crear una nueva conexión para este test
    #     new_connection = ActiveRecord::Base.connection_pool.checkout
    #     begin
    #       new_connection.transaction(isolation: :read_committed) do
    #         new_connection.execute("SELECT 1 FROM RDB$DATABASE")
    #       end
    #     ensure
    #       ActiveRecord::Base.connection_pool.checkin(new_connection)
    #     end
    #   end.not_to raise_error
    # end
  end
end
