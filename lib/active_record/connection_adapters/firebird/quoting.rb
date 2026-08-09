# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      module Quoting
        # Escape single quotes for Firebird (double single quotes)
        def quote_string(s)
          s.to_s.gsub("'", "''")
        end

        # quote_column_name and quote_table_name are defined as class methods on
        # the adapter (FirebirdAdapter.quote_column_name). Rails 8.1 calls them
        # through self.class.quote_column_name, so no instance override is
        # needed here. Override at the class level if behavior diverges.

        # Return TRUE for boolean true (Firebird 3+)
        def quoted_true
          "TRUE"
        end

        # Return FALSE for boolean false (Firebird 3+)
        def quoted_false
          "FALSE"
        end

        # Format dates and timestamps for Firebird
        def quoted_date(value)
          if value.acts_like?(:time)
            if supports_time_zones? && value.respond_to?(:in_time_zone)
              # Firebird 4+ supports timestamps with time zone
              value = value.in_time_zone
              zone = value.formatted_offset
              value.strftime("%Y-%m-%d %H:%M:%S.%6N #{zone}")
            else
              value.strftime("%Y-%m-%d %H:%M:%S.%6N")
            end
          elsif value.acts_like?(:date)
            value.strftime("%Y-%m-%d")
          else
            super
          end
        end

        # Quote binary data as hexadecimal for Firebird
        def quoted_binary(value)
          return "NULL" if value.nil?

          # Handle both string and binary data properly
          binary_value = if value.respond_to?(:force_encoding)
                           value.dup.force_encoding("BINARY")
                         else
                           value.to_s.force_encoding("BINARY")
                         end

          "x'#{binary_value.unpack1("H*")}'"
        end

        # Type cast values for Firebird
        def type_cast(value)
          case value
          when Type::Binary::Data
            # Firebird handles blobs specially
            if value.respond_to?(:force_encoding)
              value.dup.force_encoding("BINARY")
            else
              value
            end
          when String
            # Check if this should be treated as binary data
            if value.encoding == Encoding::BINARY || value.bytes.any? { |b| b < 32 && b != 0 && b != 9 && b != 10 && b != 13 }
              value.force_encoding("BINARY")
            else
              value
            end
          when true
            1
          when false
            0
          else
            super
          end
        end

        # Quote default expressions - don't quote function calls
        def quote_default_expression(value, column)
          if value.is_a?(String) && value.match?(/\A\w+\(.*\)\z/)
            # It's a function, don't quote
            value
          else
            super
          end
        end

        # Quote values for SQL
        def quote(value)
          case value
          when Type::Binary::Data
            "'#{quote_string(value.hex)}'"
          when Type::Time::Value
            "'#{quoted_date(value)}'"
          when Date, Time
            "'#{quoted_date(value)}'"
          when String
            "'#{quote_string(value)}'"
          when true
            quoted_true
          when false
            quoted_false
          when nil
            "NULL"
          when BigDecimal
            value.to_s("F")
          when Numeric
            value.to_s
          when ActiveRecord::Relation
            quote(value.to_sql)
          else
            super
          end
        end

        private

        def _quote(value)
          case value
          when Type::Binary::Data
            "'#{quote_string(value.hex)}'"
          when Type::Time::Value
            "'#{quoted_date(value)}'"
          when Date, Time
            "'#{quoted_date(value)}'"
          when String
            "'#{quote_string(value)}'"
          when true
            quoted_true
          when false
            quoted_false
          when nil
            "NULL"
          when BigDecimal
            value.to_s("F")
          when Numeric
            value.to_s
          else
            super
          end
        end

        def _type_cast(value)
          case value
          when Symbol, ActiveSupport::Multibyte::Chars
            value.to_s
          when true
            1
          when false
            0
          when Type::Binary::Data
            value.hex
          else
            super
          end
        end
      end
    end
  end
end
