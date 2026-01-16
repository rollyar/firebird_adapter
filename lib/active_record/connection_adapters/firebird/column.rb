# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      class Column < ConnectionAdapters::Column
        attr_reader :domain_name, :computed_source

        def initialize(name, default, sql_type_metadata = nil, null = true,
                       default_function: nil, collation: nil, comment: nil,
                       domain_name: nil, computed_source: nil, **options)
          @domain_name = domain_name
          @computed_source = computed_source
          super(name, default, sql_type_metadata, null,
                default_function: default_function,
                collation: collation,
                comment: comment,
                **options)
        end

        def virtual?
          # COMPUTED BY columns son virtuales en Firebird
          !@computed_source.nil?
        end

        def has_default?
          # Las columnas computadas no tienen default
          !virtual? && super
        end

        def auto_incremented?
          # Detectar si la columna usa un generador/secuencia o IDENTITY
          return false unless default_function

          # Check for IDENTITY columns (Firebird 3.0+)
          return true if @sql_type&.include?("IDENTITY")

          # Check if sql_type has IDENTITY (backup for when sql_type doesn't show full info)
          return true if @sql_type&.include?("IDENTITY")

          # Debug: log what we're checking
          puts "DEBUG: auto_incremented? checking #{@sql_type.inspect}, default_function: #{default_function.inspect}"

          # Check for traditional generator patterns
          default_function.match?(/GEN_ID|NEXT VALUE FOR/i)
        end
      end
    end
  end
end
