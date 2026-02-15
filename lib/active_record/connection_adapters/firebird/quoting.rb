# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      module Quoting
        def quote_string(s)
          s.gsub("'", "''")
        end

        def quote_column_name(name)
          name = name.to_s

          # If already quoted, return as-is
          return name if name.start_with?('"') && name.end_with?('"')

          # Quote if contains spaces or special characters, or has mixed case
          if name.match?(/[^a-zA-Z0-9_]/) || (name.match?(/[a-z]/) && name.match?(/[A-Z]/))
            "\"#{name}\""
          else
            # For Firebird, convert to UPPER_CASE for SQL
            name.upcase
          end
        end

        def quote_table_name(name)
          name = name.to_s

          # If already quoted, return as-is
          return name if name.start_with?('"') && name.end_with?('"')

          # Convert to uppercase for Firebird internal storage but quote to preserve
          "\"#{name.upcase}\""
        end

        def quoted_true
          "TRUE"
        end

        def quoted_false
          "FALSE"
        end

        def quoted_date(value)
          if value.acts_like?(:time)
            if supports_time_zones? && value.respond_to?(:in_time_zone)
              # Firebird 4+ soporta timestamps con zona horaria
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

        def quoted_binary(value)
          # Firebird usa hexadecimal para binarios
          # Handle both string and binary data properly
          if value.respond_to?(:force_encoding)
            # Ensure binary encoding
            binary_value = value.dup.force_encoding("BINARY")
            "x'#{binary_value.unpack1("H*")}'"
          else
            "x'#{value.unpack1("H*")}'"
          end
        end

        def type_cast(value)
          case value
          when Type::Binary::Data
            # Firebird maneja blobs de manera especial
            # Ensure proper encoding handling
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

        def quote_default_expression(value, column)
          if value.is_a?(String) && value.match?(/\A\w+\(.*\)\z/)
            # Es una función, no quotear
            value
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
