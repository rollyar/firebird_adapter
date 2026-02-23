# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Firebird
      module SchemaStatements
        def tables(_name = nil)
          query_values(<<~SQL, "SCHEMA")
            SELECT TRIM(RDB$RELATION_NAME)
            FROM RDB$RELATIONS
            WHERE RDB$SYSTEM_FLAG = 0
            AND RDB$VIEW_BLR IS NULL
            ORDER BY RDB$RELATION_NAME
          SQL
        end

        def views
          query_values(<<~SQL, "SCHEMA")
            SELECT TRIM(RDB$RELATION_NAME)
            FROM RDB$RELATIONS
            WHERE RDB$SYSTEM_FLAG = 0
            AND RDB$VIEW_BLR IS NOT NULL
            ORDER BY RDB$RELATION_NAME
          SQL
        end

        def table_exists?(table_name)
          table_name = table_name.to_s.upcase
          result = query_value(<<~SQL)
            SELECT COUNT(*)
            FROM RDB$RELATIONS
            WHERE RDB$RELATION_NAME = '#{table_name}'
            AND RDB$SYSTEM_FLAG = 0
          SQL
          result = result.first if result.is_a?(Array)
          result.to_i.positive?
        end

        def view_exists?(view_name)
          query_value(<<~SQL, "SCHEMA") == 1
            SELECT COUNT(*)
            FROM RDB$RELATIONS
            WHERE UPPER(TRIM(RDB$RELATION_NAME)) = UPPER('#{view_name.to_s.upcase}')
            AND RDB$VIEW_BLR IS NOT NULL
          SQL
        end

        def indexes(table_name)
          result = query(<<~SQL, "SCHEMA")
            SELECT DISTINCT
              TRIM(i.RDB$INDEX_NAME) as index_name,
              i.RDB$UNIQUE_FLAG as is_unique,
              TRIM(seg.RDB$FIELD_NAME) as column_name,
              i.RDB$INDEX_TYPE as index_type,
              NULL as condition
            FROM RDB$INDICES i
            JOIN RDB$INDEX_SEGMENTS seg ON i.RDB$INDEX_NAME = seg.RDB$INDEX_NAME
            WHERE UPPER(TRIM(i.RDB$RELATION_NAME)) = UPPER('#{table_name.to_s.upcase}')
            AND i.RDB$SYSTEM_FLAG = 0
            ORDER BY i.RDB$INDEX_NAME, seg.RDB$FIELD_POSITION
          SQL

          result.group_by { |row| row[0] }.map do |index_name, rows|
            IndexDefinition.new(
              table_name,
              index_name,
              rows.first[1] == 1,
              rows.map { |r| r[2] },
              where: rows.first[4]&.strip.presence
            )
          end
        end

        def column_definitions(table_name)
          requested = table_name.to_s
          unless table_exists?(requested)
            alt = requested.pluralize
            alt2 = requested.end_with?("s") ? requested.chomp("s") : "#{requested}s"

            if table_exists?(alt)
              requested = alt
            elsif table_exists?(alt2)
              requested = alt2
            else
              raise StatementInvalid, "Table #{table_name} does not exist"
            end
          end
          table_name = requested

          sql = <<~SQL
            SELECT
              r.rdb$field_name,
              r.rdb$null_flag,
              r.rdb$default_source,
              f.rdb$field_type,
              f.rdb$field_length,
              f.rdb$field_scale,
              f.rdb$field_sub_type,
              f.rdb$character_set_id,
              c.rdb$collation_name,
              NULL as rdb$time_zone,
              f.rdb$computed_source
            FROM rdb$relation_fields r
            JOIN rdb$fields f ON r.rdb$field_source = f.rdb$field_name
            LEFT JOIN rdb$collations c ON f.rdb$collation_id = c.rdb$collation_id
              AND f.rdb$character_set_id = c.rdb$character_set_id
            WHERE r.rdb$relation_name = '#{table_name.to_s.upcase}'
            ORDER BY r.rdb$field_position
          SQL

          result = query(sql, "SCHEMA")
          result = result.first while result.is_a?(Array) && result.length == 1 && result.first.is_a?(Array)

          result.map do |row|
            field_name = scalar_value(row[0])&.strip
            ruby_field_name = field_name.underscore
            null_flag = scalar_value(row[1])
            default_source = scalar_value(row[2])
            field_type = scalar_value(row[3])
            field_length = scalar_value(row[4])
            field_scale = scalar_value(row[5])
            field_sub_type = scalar_value(row[6])
            character_set_id = scalar_value(row[7])
            collation_name = scalar_value(row[8])
            computed_source = scalar_value(row[10])

            sql_type = case field_type
                       when 261
                         field_sub_type == 1 ? "BLOB SUB_TYPE TEXT" : "BLOB SUB_TYPE BINARY"
                       when 14
                         "CHAR(#{field_length})"
                       when 37
                         "VARCHAR(#{field_length})"
                       when 7
                         "SMALLINT"
                       when 8
                         "INTEGER"
                       when 16
                         if field_sub_type == 2 || (field_sub_type == 1 && field_scale && field_scale < 0)
                           scale = field_scale ? field_scale.abs : 0
                           precision = field_length || 18
                           scale > 0 ? "NUMERIC(#{precision},#{scale})" : "NUMERIC(#{precision})"
                         elsif field_sub_type == 1
                           computed_source_value = scalar_value(row[10])
                           if computed_source_value&.include?("IDENTITY")
                             "BIGINT GENERATED BY DEFAULT AS IDENTITY"
                           else
                             "BIGINT"
                           end
                         else
                           "BIGINT"
                         end
                       when 23
                         "BOOLEAN"
                       when 12
                         "DATE"
                       when 13
                         "TIME"
                       when 35
                         "TIMESTAMP"
                       when 10
                         "FLOAT"
                       when 27
                         "DOUBLE PRECISION"
                       when 37
                         field_scale && field_scale > 0 ? "DECFLOAT(#{field_scale})" : "DECFLOAT(16)"
                       when 794
                         field_scale && field_scale > 0 ? "DECIMAL(#{field_length || 18},#{field_scale})" : "DECIMAL(18,0)"
                       else
                         "VARCHAR(#{field_length || 255})"
                       end

            {
              field_name: ruby_field_name,
              original_field_name: field_name,
              null_flag: null_flag,
              default_source: default_source,
              field_type: field_type,
              field_length: field_length,
              field_scale: field_scale,
              field_sub_type: field_sub_type,
              character_set_id: character_set_id,
              collation_name: collation_name,
              computed_source: computed_source,
              sql_type: sql_type
            }
          end
        end

        def columns(table_name)
          table_name = table_name.to_s
          definitions = column_definitions(table_name)
          definitions.map { |field| new_column_from_field(table_name, field, definitions) }
        end

        def new_column_from_field(table_name, field, _definitions)
          field_name = field[:field_name]
          sql_type = field[:sql_type]
          null_flag = field[:null_flag]
          default_source = field[:default_source]
          computed_source = field[:computed_source]

          field_name = field_name.downcase if respond_to?(:downcase_columns?) && downcase_columns?

          default_value = extract_value_from_default(default_source)
          default_function = extract_default_function(default_value, default_source)

          type_metadata = fetch_type_metadata(sql_type)
          nullable = null_flag.nil? || null_flag == 0

          primary_keys = primary_keys(table_name.to_s)
          is_primary_key = primary_keys.include?(field_name.strip) ||
                           (field_name.strip.downcase == "id" && primary_keys.any? { |pk| pk.downcase == "id" })

          Firebird::Column.new(
            field_name,
            default_value,
            type_metadata,
            nullable,
            default_function: default_function,
            computed_source: computed_source,
            primary_key: is_primary_key
          )
        end

        def scalar_value(value)
          value = value.first while value.is_a?(Array)
          value
        end

        def primary_keys(table_name)
          query_values(<<~SQL, "SCHEMA")
            SELECT TRIM(seg.RDB$FIELD_NAME)
            FROM RDB$RELATION_CONSTRAINTS rc
            JOIN RDB$INDICES idx ON rc.RDB$INDEX_NAME = idx.RDB$INDEX_NAME
            JOIN RDB$INDEX_SEGMENTS seg ON idx.RDB$INDEX_NAME = seg.RDB$INDEX_NAME
            WHERE rc.RDB$RELATION_NAME = '#{table_name.to_s.upcase}'
            AND rc.RDB$CONSTRAINT_TYPE = 'PRIMARY KEY'
            ORDER BY seg.RDB$FIELD_POSITION
          SQL
        end

        def foreign_keys(table_name)
          fk_info = query(<<~SQL, "SCHEMA")
            SELECT DISTINCT
              TRIM(rc.RDB$CONSTRAINT_NAME) as name,
              TRIM(cse.RDB$FIELD_NAME) as column,
              TRIM(ref_rel.RDB$RELATION_NAME) as to_table,
              TRIM(ref_seg.RDB$FIELD_NAME) as primary_key,
              TRIM(ref_const.RDB$UPDATE_RULE) as on_update,
              TRIM(ref_const.RDB$DELETE_RULE) as on_delete
            FROM RDB$RELATION_CONSTRAINTS rc
            JOIN RDB$REF_CONSTRAINTS ref_const ON rc.RDB$CONSTRAINT_NAME = ref_const.RDB$CONSTRAINT_NAME
            JOIN RDB$RELATION_CONSTRAINTS ref_rel_const ON ref_const.RDB$CONST_NAME_UQ = ref_rel_const.RDB$CONSTRAINT_NAME
            JOIN RDB$RELATIONS ref_rel ON ref_rel_const.RDB$RELATION_NAME = ref_rel.RDB$RELATION_NAME
            JOIN RDB$INDEX_SEGMENTS cse ON rc.RDB$INDEX_NAME = cse.RDB$INDEX_NAME
            JOIN RDB$INDEX_SEGMENTS ref_seg ON ref_rel_const.RDB$INDEX_NAME = ref_seg.RDB$INDEX_NAME
              AND cse.RDB$FIELD_POSITION = ref_seg.RDB$FIELD_POSITION
            WHERE UPPER(TRIM(rc.RDB$RELATION_NAME)) = UPPER('#{table_name.to_s.upcase}')
            AND rc.RDB$CONSTRAINT_TYPE = 'FOREIGN KEY'
            ORDER BY rc.RDB$CONSTRAINT_NAME, cse.RDB$FIELD_POSITION
          SQL

          fk_info.group_by { |row| row[0] }.map do |fk_name, rows|
            options = {
              name: fk_name,
              column: rows.map { |r| r[1] },
              primary_key: rows.map { |r| r[3] }
            }

            options[:on_update] = convert_fk_action(rows.first[4])
            options[:on_delete] = convert_fk_action(rows.first[5])

            ForeignKeyDefinition.new(table_name, rows.first[2], options)
          end
        end

        def create_table(table_name, id: :primary_key, primary_key: nil, force: nil, **options)
          td = super

          return td unless options[:sequence] != false && id != false

          sequence_name = options[:sequence] || default_sequence_name(table_name)
          create_sequence(sequence_name)

          td
        end

        def drop_table(table_name, if_exists: false, **_options)
          return unless table_exists?(table_name) || !if_exists

          begin
            commit_db_transaction if transaction_open?
            execute("DROP TABLE #{quote_table_name(table_name)}")
          rescue ::Fb::Error => e
            return if if_exists && e.message.include?("object TABLE") && e.message.include?("is in use")
            raise unless if_exists
          end
        end

        def add_column(table_name, column_name, type, **options)
          sql_type = type_to_sql(type, **options.slice(:limit, :precision, :scale))

          sql = "ALTER TABLE #{quote_table_name(table_name)} ADD #{quote_column_name(column_name)} #{sql_type}"

          if options[:null] == false
            sql << " NOT NULL"
          elsif options[:null] == true
            sql << " NULL"
          end

          execute(sql)

          change_column_default(table_name, column_name, options[:default]) if options[:default]

          return unless !supports_identity_columns? && (options[:auto_increment] || options[:primary_key])

          create_sequence_for_column(table_name, column_name)
        end

        def change_column(table_name, column_name, type, **options)
          column_for(table_name, column_name)

          type_sql = type_to_sql(type, **options.slice(:limit, :precision, :scale))
          execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} TYPE #{type_sql}")

          if options.key?(:null)
            if options[:null]
              execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} DROP NOT NULL")
            else
              execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} SET NOT NULL")
            end
          end

          change_column_default(table_name, column_name, options[:default]) if options.key?(:default)
        end

        def change_column_default(table_name, column_name, default_or_changes)
          default = extract_new_default_value(default_or_changes)

          if default.nil?
            execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} DROP DEFAULT")
          else
            execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} SET DEFAULT #{quote(default)}")
          end
        end

        def change_column_null(table_name, column_name, null, default = nil)
          if null
            execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} DROP NOT NULL")
          else
            change_column_default(table_name, column_name, default) if default
            if default
              execute("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)} = #{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
            end
            execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} SET NOT NULL")
          end
        end

        def rename_column(table_name, column_name, new_column_name)
          execute("ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} TO #{quote_column_name(new_column_name)}")
        end

        def remove_column(table_name, column_name, _type = nil, **_options)
          execute("ALTER TABLE #{quote_table_name(table_name)} DROP #{quote_column_name(column_name)}")
        end

        def add_index(table_name, column_name, **options)
          index_name, index_type, index_columns, = add_index_options(table_name, column_name, **options)
          sql = "CREATE #{index_type}INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)} (#{index_columns})"
          sql << " WHERE #{options[:where]}" if supports_partial_index? && options[:where]
          execute(sql)
        end

        def remove_index(table_name, column_name = nil, **options)
          index_name = index_name_for_remove(table_name, column_name, options)
          execute("DROP INDEX #{quote_column_name(index_name)}")
        end

        def rename_table(table_name, new_name)
          table_name = table_name.to_s
          new_name = new_name.to_s

          raise TableNotFound, "Table #{table_name} does not exist" unless table_exists?(table_name)

          original_columns = column_definitions(table_name)
          column_defs = original_columns.map do |col|
            "#{quote_column_name(col[:original_field_name] || col[:field_name])} #{col[:sql_type]}"
          end.join(", ")

          execute("CREATE TABLE #{quote_table_name(new_name)} (#{column_defs})")

          columns_list = original_columns.map do |col|
            quote_column_name(col[:original_field_name] || col[:field_name])
          end.join(", ")
          execute("INSERT INTO #{quote_table_name(new_name)} (#{columns_list}) SELECT #{columns_list} FROM #{quote_table_name(table_name)}")

          execute("DROP TABLE #{quote_table_name(table_name)}")
        rescue StandardError => e
          raise NotImplementedError, "Failed to rename table: #{e.message}"
        end

        def create_sequence(sequence_name, start_value: 1)
          execute("CREATE SEQUENCE #{quote_table_name(sequence_name)}")
          execute("ALTER SEQUENCE #{quote_table_name(sequence_name)} RESTART WITH #{start_value}")
        rescue StandardError
          nil
        end

        def drop_sequence(sequence_name)
          execute("DROP SEQUENCE #{quote_table_name(sequence_name)}")
        rescue StandardError
          nil
        end

        def sequence_exists?(sequence_name)
          query_value(<<~SQL, "SCHEMA") == 1
            SELECT COUNT(*)
            FROM RDB$GENERATORS
            WHERE UPPER(TRIM(RDB$GENERATOR_NAME)) = UPPER('#{sequence_name.to_s.upcase}')
            AND RDB$SYSTEM_FLAG = 0
          SQL
        end

        def default_sequence_name(table_name, _column = nil)
          "#{table_name}_seq"
        end

        def next_sequence_value(sequence_name)
          @connection.query("SELECT NEXT VALUE FOR #{quote_table_name(sequence_name)}  FROM RDB$DATABASE")[0][0]
        end

        def check_constraints(table_name)
          query(<<~SQL, "SCHEMA")
                SELECT TRIM(con.RDB$CONSTRAINT_NAME), TRIM(chk.RDB$TRIGGER_SOURCE)
                FROM RDB$CHECK_CONSTRAINTS chk
                JOIN RDB$RELATION_CONSTRAINTS con ON chk.RDB$CONSTRAINT_NAME = con.RDB$CONSTRAINT_NAME
                WHERE UPPER(TRIM(con.RDB$RELATION_NAME)) = UPPER('#{table_name.to_s.upcase}')
                AND con.RDB$CONSTRAINT_TYPE = 'CHECK'
              SQL.map { |row| CheckConstraintDefinition.new(table_name, row[0].strip, row[1].strip) }
            end

            def add_check_constraint(table_name, expression, **options)
              constraint_name = check_constraint_name(table_name, **options)
              execute("ALTER TABLE #{quote_table_name(table_name)} ADD CONSTRAINT #{quote_column_name(constraint_name)} CHECK (#{expression})")
            end

            def remove_check_constraint(table_name, **options)
              constraint_name = check_constraint_name(table_name, **options)
              execute("ALTER TABLE #{quote_table_name(table_name)} DROP CONSTRAINT #{quote_column_name(constraint_name)}")
            end

            def add_column_comment(table_name, column_name, comment)
              return if comment.blank?
              execute("COMMENT ON COLUMN #{quote_table_name(table_name)}.#{quote_column_name(column_name)} IS '#{comment.gsub("'", "''")}'")
            end

            def add_table_comment(table_name, comment)
              return if comment.blank?
              execute("COMMENT ON TABLE #{quote_table_name(table_name)} IS '#{comment.gsub("'", "''")}'")
            end

            def fetch_type_metadata(sql_type)
              TypeMetadata.new(sql_type: sql_type.to_s, adapter: self)
            end

            private

            def create_sequence_for_pk(table_name, column_name)
              sequence_name = default_sequence_name(table_name, column_name)
              create_sequence(sequence_name) unless sequence_exists?(sequence_name)

              trigger_name = "#{table_name}_#{column_name}_trig".upcase
              execute(<<~SQL)
                CREATE TRIGGER #{trigger_name} FOR #{quote_table_name(table_name)}
                ACTIVE BEFORE INSERT POSITION 0
                AS
                BEGIN
                  IF (NEW.#{quote_column_name(column_name)} IS NULL) THEN
                    NEW.#{quote_column_name(column_name)} = NEXT VALUE FOR #{sequence_name};
                END
          SQL
        end

        def create_sequence_for_column(table_name, column_name)
          create_sequence_for_pk(table_name, column_name)
        end

        def convert_fk_action(action)
          case action&.strip
          when "CASCADE" then :cascade
          when "SET NULL" then :nullify
          when "SET DEFAULT" then :restrict
          else :no_action
          end
        end

        def extract_new_default_value(default_or_changes)
          default_or_changes.is_a?(Hash) ? default_or_changes[:to] : default_or_changes
        end

        def extract_default_function(default_value, default)
          return default if default_value.present?
          return default if default.present?

          nil
        end

        def unwrap_value(value)
          value = value[0] while value.is_a?(Array) && value.length == 1
          value&.strip
        end
      end
    end
  end
end
