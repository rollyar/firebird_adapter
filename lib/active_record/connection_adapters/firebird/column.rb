# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      class Column < ConnectionAdapters::Column
        attr_reader :domain_name, :computed_source, :primary_key

        def initialize(name, default, sql_type_metadata = nil, null = true,
                       default_function: nil, collation: nil, comment: nil,
                       domain_name: nil, computed_source: nil, primary_key: false, **options)
          @domain_name = domain_name
          @computed_source = computed_source
          @primary_key = primary_key
          super(name, default, sql_type_metadata, null,
                default_function: default_function,
                collation: collation,
                comment: comment,
                primary_key: primary_key,
                **options)
        end

        def virtual?
          # COMPUTED BY columns are virtual in Firebird
          !@computed_source.nil?
        end

        def has_default?
          # Computed columns don't have defaults
          !virtual? && super
        end

        def auto_incremented_by_db?
          auto_incremented?
        end

        def auto_incremented?
          # Check for IDENTITY columns (Firebird 3.0+)
          return true if sql_type.include?("IDENTITY")

          # Check if this is a primary key column (IDENTITY columns don't have default_function)
          return true if sql_type.include?("BIGINT") && @primary_key

          # Check for traditional generator patterns
          return true if default_function&.match?(/GEN_ID|NEXT VALUE FOR/i)

          false
        end
      end
    end
  end
end
