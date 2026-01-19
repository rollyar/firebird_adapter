# frozen_string_literal: true

# Configuración para usuarios no-SYSDBA en Firebird
module FirebirdAdapter
  module UserAccess
    # Configuración para diferentes usuarios y roles
    USER_CONFIGS = {
      # Usuario básico con permisos limitados
      basic_user: {
        username: "BASIC_USER",
        password: "basic_pass",
        role: nil,
        permissions: %w[SELECT INSERT UPDATE DELETE]
      },

      # Usuario de solo lectura
      readonly_user: {
        username: "READONLY_USER",
        password: "read_pass",
        role: "READONLY_ROLE",
        permissions: ["SELECT"]
      },

      # Usuario con permisos de escritura
      writer_user: {
        username: "WRITER_USER",
        password: "write_pass",
        role: "WRITER_ROLE",
        permissions: %w[SELECT INSERT UPDATE DELETE]
      },

      # Usuario administrador (no SYSDBA)
      admin_user: {
        username: "ADMIN_USER",
        password: "admin_pass",
        role: "ADMIN_ROLE",
        permissions: %w[SELECT INSERT UPDATE DELETE CREATE ALTER DROP]
      }
    }.freeze

    def self.connection_config(user_type = :basic_user, database_path)
      config = USER_CONFIGS[user_type]
      raise "Unknown user type: #{user_type}" unless config

      {
        adapter: "firebird",
        database: database_path,
        username: config[:username],
        password: config[:password],
        role: config[:role],
        charset: "UTF8",
        downcase: true
      }
    end

    def self.create_user_sql(user_type)
      config = USER_CONFIGS[user_type]
      raise "Unknown user type: #{user_type}" unless config

      sql = <<~SQL
        -- Crear usuario
        CREATE USER #{config[:username]} PASSWORD '#{config[:password]}';

        -- Crear rol si es necesario
        #{"CREATE ROLE #{config[:role]};" if config[:role]}

        -- Asignar rol al usuario
        #{"GRANT #{config[:role]} TO #{config[:username]};" if config[:role]}
      SQL

      sql.strip
    end

    def self.grant_permissions_sql(table_name, user_type)
      config = USER_CONFIGS[user_type]
      raise "Unknown user type: #{user_type}" unless config

      permissions = config[:permissions].join(", ")
      table_name.upcase!

      <<~SQL
        GRANT #{permissions} ON #{table_name} TO #{config[:username]};
      SQL
    end
  end
end
