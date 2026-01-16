# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      class TypeMetadata < ::ActiveRecord::ConnectionAdapters::SqlTypeMetadata
        attr_reader :adapter

        def initialize(sql_type:, limit: nil, precision: nil, scale: nil, adapter: nil)
          super(sql_type: sql_type, limit: limit, precision: precision, scale: scale)
          @adapter = adapter
        end

        def sql_type
          case super
          when "timestamp with time zone"
            adapter&.supports_time_zones? ? "timestamp with time zone" : "timestamp"
          when "time with time zone"
            adapter&.supports_time_zones? ? "time with time zone" : "time"
          when "int128"
            adapter&.supports_int128? ? "int128" : "bigint"
          else
            super
          end
        end

        def ==(other)
          other.is_a?(TypeMetadata) &&
            super(other) &&
            adapter == other.adapter
        end
        alias eql? ==

        def hash
          super ^ adapter.hash
        end

        def dup
          self.class.new(
            sql_type: super(),
            limit: limit,
            precision: precision,
            scale: scale,
            adapter: @adapter
          )
        end

        alias clone dup
      end
    end
  end
end
