# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      class Column < ConnectionAdapters::Column
        attr_reader :domain_name, :computed_source, :primary_key

        def initialize(name, cast_type, default, sql_type_metadata = nil, null = true,
                       default_function = nil, collation: nil, comment: nil,
                       domain_name: nil, computed_source: nil, primary_key: false, **options)
          @domain_name = domain_name
          @computed_source = computed_source
          @primary_key = primary_key
          super(name, cast_type, default, sql_type_metadata, null, default_function,
                collation: collation,
                comment: comment,
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
          # Firebird 3+ IDENTITY columns
          return true if sql_type.include?("IDENTITY") || sql_type.include?("GENERATED")

          # Sequence/trigger-based PK (set up by create_table with id: :primary_key)
          return true if @primary_key && default_function&.match?(/GEN_ID|NEXT VALUE FOR/i)

          false
        end
      end
    end
  end
end
