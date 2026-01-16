# spec/spec_helper.rb
require "bundler/setup"
require "active_record"
require "fb"
require "firebird_adapter"
require "database_cleaner/active_record"
require "rspec"

DB_PATH = File.expand_path("test.fdb", __dir__)

# Definir SisTest fuera de los bloques de configuración
class SisTest < ActiveRecord::Base
  self.table_name = "sis_test"
  self.primary_key = "id_test"
end

RSpec.configure do |config|
  config.before(:suite) do
    # 1. Crear base de datos limpia
    File.delete(DB_PATH) if File.exist?(DB_PATH)

    begin
      ::Fb::Database.create(
        database: DB_PATH,
        user: "SYSDBA",
        password: "masterkey"
      )
    rescue StandardError => e
      puts "Error creando base de datos: #{e.message}"
    end

    db_config = {
      adapter: "firebird",
      database: DB_PATH,
      username: "sysdba",
      password: "masterkey",
      charset: "UTF8",
      # Normalizar nombres de columnas a minúsculas para ActiveRecord
      downcase: true
    }

    # 2. Conectar ActiveRecord
    begin
      ActiveRecord::Base.establish_connection(db_config)

      # Forzar la conexión
      connection = ActiveRecord::Base.connection
      puts "Conexión establecida: #{connection.active?}"

      # 3. Crear tablas de prueba SOLO si no existen
      unless connection.table_exists?(:sis_tests)
        connection.execute(<<-SQL)
          CREATE TABLE sis_tests (
            id BIGINT NOT NULL PRIMARY KEY,
            id_test BIGINT,
            field_varchar VARCHAR(255),
            field_char CHAR(10),
            field_date DATE,
            field_smallint INTEGER,
            field_integer INTEGER,
            field_double_precision DOUBLE PRECISION,
            field_blob_text BLOB SUB_TYPE TEXT,
            field_blob_binary BLOB SUB_TYPE BINARY
          )
        SQL
        puts "Tabla sis_tests creada"
      end

      # Reset column information
      SisTest.reset_column_information
      puts "SisTest.table_name=#{SisTest.table_name.inspect}"
    rescue StandardError => e
      puts "Error en configuración: #{e.message}"
      puts e.backtrace.take(5).join("\n")
    end
  end

  config.after(:suite) do
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?

    # Limpiar archivo de base de datos
    File.delete(DB_PATH) if File.exist?(DB_PATH)
  rescue StandardError => e
    puts "Error desconectando: #{e.message}"
  end

  # Configuración para cada test - SOLO limpiar datos, no eliminar tablas
  config.before(:each) do
    # Solo limpiar datos si la tabla existe
    if ActiveRecord::Base.connection.table_exists?(:sis_tests)
      ActiveRecord::Base.connection.execute("DELETE FROM SIS_TESTS")
    end
  end
end
