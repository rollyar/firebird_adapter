# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      class TableDefinition < ActiveRecord::ConnectionAdapters::TableDefinition
        # Columnas específicas de Firebird

        def int128(*args, **options)
          args.each { |name| column(name, :int128, **options) }
        end

        def timestamptz(*args, **options)
          args.each { |name| column(name, :timestamptz, **options) }
        end

        def timetz(*args, **options)
          args.each { |name| column(name, :timetz, **options) }
        end

        def computed_by(name, expression, **options)
          column(name, :computed, computed_by: expression, **options)
        end

        private

        def create_column_definition(name, type, options = {})
          if type == :computed
            Firebird::ColumnDefinition.new(name, type, **options)
          else
            super
          end
        end
      end

      class ColumnDefinition < ActiveRecord::ConnectionAdapters::ColumnDefinition
        attr_accessor :computed_by

        def initialize(name, type, **options)
          @computed_by = options.delete(:computed_by)
          super
        end

        def virtual?
          !@computed_by.nil?
        end
      end

      class SchemaCreation < ActiveRecord::ConnectionAdapters::SchemaCreation
        private

        def visit_ColumnDefinition(o)
          if o.respond_to?(:computed_by) && o.computed_by
            # COMPUTED BY columns en Firebird
            "#{quote_column_name(o.name)} COMPUTED BY (#{o.computed_by})"

          else
            super
          end
        end

        def visit_TableDefinition(o)
          create_sql = "CREATE #{"GLOBAL TEMPORARY " if o.temporary}TABLE "
          create_sql << "#{quote_table_name(o.name)} "

          statements = o.columns.map { |c| accept(c) }
          statements << accept(o.primary_keys) if o.primary_keys

          create_sql << "(#{statements.join(", ")})"

          # Firebird soporta ON COMMIT para tablas temporales
          create_sql << " ON COMMIT DELETE ROWS" if o.temporary

          create_sql
        end

        def add_column_options!(sql, options)
          # Firebird no soporta todas las opciones en CREATE TABLE
          # Algunas deben agregarse con ALTER después

          column = options.fetch(:column) { return super }

          if column.respond_to?(:virtual?) && column.virtual?
            # Las columnas COMPUTED BY no llevan más opciones
            return sql
          end

          # NULL/NOT NULL
          sql << " NOT NULL" if options[:null] == false

          # DEFAULT - pero no para columnas auto-incrementadas
          if options.key?(:default) && !options[:auto_increment]
            default = options[:default]
            sql << " DEFAULT #{quote_default_expression(default, column)}"
          end

          # COLLATE
          sql << " COLLATE #{options[:collation]}" if options[:collation]

          sql
        end

        def visit_AddColumnDefinition(o)
          sql = "ADD #{accept(o.column)}"
          add_column_options!(sql, column_options(o.column))
        end

        def visit_ChangeColumnDefinition(o)
          column = o.column
          "ALTER COLUMN #{quote_column_name(column.name)} TYPE #{type_to_sql(column.type, **column.options)}"
        end

        def action_sql(_action, dependency)
          case dependency
          when :nullify then "SET NULL"
          when :cascade then "CASCADE"
          when :restrict then "RESTRICT"
          else "NO ACTION"
          end
        end
      end

      class AlterTable < ActiveRecord::ConnectionAdapters::AlterTable
        # Firebird requiere statements separados para muchas alteraciones
        attr_reader :column_modifications

        def initialize(td)
          super
          @column_modifications = []
        end

        def modify_column(name, type, **options)
          @column_modifications << ModifyColumnDefinition.new(name, type, **options)
        end
      end

      class ModifyColumnDefinition < Struct.new(:name, :type, :options)
        def column
          @column ||= Firebird::ColumnDefinition.new(name, type, **options)
        end
      end
    end
  end
end
