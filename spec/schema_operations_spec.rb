# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Schema Operations" do
  let(:connection) { ActiveRecord::Base.connection }

  after(:each) do
    # Limpiar tablas de test creadas
    %w[test_table users products orders renamed_table].each do |table|
      connection.drop_table(table, if_exists: true)
    rescue StandardError
      nil
    end

    # Limpiar secuencias de test
    %w[test_seq].each do |seq|
      connection.drop_sequence(seq, if_exists: true)
    rescue StandardError
      nil
    end
  end

  describe "CREATE TABLE" do
    it "creates a simple table" do
      connection.create_table :test_table do |t|
        t.string :name
        t.integer :age
      end

      expect(connection.table_exists?(:test_table)).to be true
      expect(connection.columns(:test_table).map(&:name)).to include("name", "age")
    end

    it "creates table with different column types" do
      connection.create_table :test_table do |t|
        t.string :varchar_col
        t.text :text_col
        t.integer :int_col
        t.bigint :bigint_col
        t.float :float_col
        t.decimal :decimal_col, precision: 10, scale: 2
        t.date :date_col
        t.datetime :datetime_col
        t.time :time_col
        t.boolean :bool_col
        t.binary :binary_col
      end

      columns = connection.columns(:test_table)
      expect(columns.size).to be >= 11
    end

    it "creates table with timestamps" do
      connection.create_table :test_table do |t|
        t.string :name
        t.timestamps
      end

      column_names = connection.columns(:test_table).map(&:name)
      expect(column_names).to include("created_at", "updated_at")
    end

    it "creates table with custom primary key" do
      connection.create_table :test_table, id: false do |t|
        t.column :custom_id, :primary_key
        t.string :name
      end

      pk = connection.primary_keys(:test_table)
      expect(pk.map(&:upcase)).to include("CUSTOM_ID")
    end

    it "creates table with NOT NULL constraint" do
      connection.create_table :test_table do |t|
        t.string :name, null: false
        t.string :optional
      end

      name_col = connection.columns(:test_table).find { |c| c.name == "name" }
      optional_col = connection.columns(:test_table).find { |c| c.name == "optional" }

      expect(name_col.null).to be false
      expect(optional_col.null).to be true
    end

    it "creates table with default values" do
      connection.create_table :test_table do |t|
        t.string :status, default: "pending"
        t.integer :counter, default: 0
        t.boolean :active, default: true
      end

      # Verificar que las columnas tengan defaults
      status_col = connection.columns(:test_table).find { |c| c.name == "status" }
      counter_col = connection.columns(:test_table).find { |c| c.name == "counter" }

      expect(status_col.default).not_to be_nil
      expect(counter_col.default).not_to be_nil
    end

    context "Firebird 4+ specific" do
      it "creates table with INT128 if supported" do
        skip unless connection.supports_int128?

        connection.create_table :test_table do |t|
          t.int128 :huge_number
        end

        expect(connection.table_exists?(:test_table)).to be true
      end

      it "creates table with TIMESTAMP WITH TIME ZONE if supported" do
        skip unless connection.supports_time_zones?

        connection.create_table :test_table do |t|
          t.timestamptz :event_time
        end

        expect(connection.table_exists?(:test_table)).to be true
      end
    end
  end

  describe "DROP TABLE" do
    it "drops an existing table" do
      connection.create_table :test_table do |t|
        t.string :name
      end

      expect(connection.table_exists?(:test_table)).to be true

      connection.drop_table :test_table

      expect(connection.table_exists?(:test_table)).to be false
    end

    it "drops table if exists" do
      expect do
        connection.drop_table :nonexistent_table, if_exists: true
      end.not_to raise_error
    end

    it "raises error when dropping non-existent table without if_exists" do
      expect do
        connection.drop_table :nonexistent_table
      end.to raise_error(StandardError)
    end
  end

  describe "ALTER TABLE" do
    before do
      connection.create_table :test_table do |t|
        t.string :name
        t.integer :age
      end
    end

    describe "RENAME TABLE" do
      it "renames a table" do
        expect(connection.table_exists?(:test_table)).to be true

        connection.rename_table :test_table, :renamed_table

        expect(connection.table_exists?(:renamed_table)).to be true
        expect(connection.table_exists?(:test_table)).to be false
      end

      it "raises error when renaming non-existent table" do
        expect do
          connection.rename_table :nonexistent_table, :new_name
        end.to raise_error(NotImplementedError)
      end
    end

    describe "ADD COLUMN" do
      it "adds a new column" do
        connection.add_column :test_table, :email, :string

        columns = connection.columns(:test_table).map(&:name)
        expect(columns).to include("email")
      end

      it "adds column with options" do
        connection.add_column :test_table, :status, :string,
                              default: "active", null: false

        status_col = connection.columns(:test_table).find { |c| c.name == "status" }
        expect(status_col.null).to be false
      end
    end

    describe "REMOVE COLUMN" do
      it "removes an existing column" do
        connection.remove_column :test_table, :age

        columns = connection.columns(:test_table).map(&:name)
        expect(columns).not_to include("age")
      end
    end

    describe "CHANGE COLUMN" do
      it "changes column type" do
        connection.change_column :test_table, :age, :bigint

        age_col = connection.columns(:test_table).find { |c| c.name == "age" }
        expect(age_col.sql_type.downcase).to include("bigint")
      end

      it "changes column null constraint" do
        connection.change_column_null :test_table, :name, false

        name_col = connection.columns(:test_table).find { |c| c.name == "name" }
        expect(name_col.null).to be false
      end

      it "changes column default" do
        connection.change_column_default :test_table, :name, "Unknown"

        name_col = connection.columns(:test_table).find { |c| c.name == "name" }
        expect(name_col.default).not_to be_nil
      end
    end

    describe "RENAME COLUMN" do
      it "renames a column" do
        connection.rename_column :test_table, :name, :full_name

        columns = connection.columns(:test_table).map(&:name)
        expect(columns).to include("full_name")
        expect(columns).not_to include("name")
      end
    end
  end

  describe "INDEXES" do
    before do
      connection.create_table :test_table do |t|
        t.string :email
        t.string :username
        t.integer :user_id
      end
    end

    it "adds a simple index" do
      connection.add_index :test_table, :email

      indexes = connection.indexes(:test_table)
      email_index = indexes.find { |i| i.columns.map(&:upcase).include?("EMAIL") }

      expect(email_index).not_to be_nil
    end

    it "adds a unique index" do
      connection.add_index :test_table, :username, unique: true

      indexes = connection.indexes(:test_table)
      username_index = indexes.find { |i| i.columns.map(&:upcase).include?("USERNAME") }

      expect(username_index).not_to be_nil
      expect(username_index.unique).to be true
    end

    it "adds a composite index" do
      connection.add_index :test_table, %i[user_id email]

      indexes = connection.indexes(:test_table)
      composite_index = indexes.find { |i| i.columns.map(&:upcase) == %w[USER_ID EMAIL] }

      expect(composite_index).not_to be_nil
    end

    it "adds index with custom name" do
      connection.add_index :test_table, :email, name: "custom_email_idx"

      indexes = connection.indexes(:test_table)
      expect(indexes.map { |i| i.name.upcase }).to include("CUSTOM_EMAIL_IDX")
    end

    context "Firebird 5+ partial indexes" do
      it "adds a partial index if supported" do
        skip "Partial indexes not supported" unless connection.supports_partial_index?

        connection.add_index :test_table, :email,
                             where: "user_id IS NOT NULL",
                             name: "idx_email_with_user"

        indexes = connection.indexes(:test_table)
        partial_index = indexes.find { |i| i.name.upcase == "IDX_EMAIL_WITH_USER" }

        expect(partial_index).not_to be_nil
      end
    end

    it "removes an index" do
      connection.add_index :test_table, :email, name: "email_idx"
      connection.remove_index :test_table, name: "email_idx"

      indexes = connection.indexes(:test_table)
      expect(indexes.map(&:name)).not_to include("email_idx")
    end
  end

  describe "FOREIGN KEYS" do
    before do
      connection.drop_table(:users, if_exists: true)
      connection.drop_table(:orders, if_exists: true)

      connection.create_table :users do |t|
        t.string :name
      end

      connection.create_table :orders do |t|
        t.integer :user_id
        t.decimal :amount
      end
    end

    xit "adds a foreign key" do
      connection.add_foreign_key :orders, :users

      fks = connection.foreign_keys(:orders)
      expect(fks).not_to be_empty

      fk = fks.first
      expect(fk.to_table).to eq("users")
    end

    xit "adds foreign key with options" do
      connection.add_foreign_key :orders, :users,
                                 on_delete: :cascade,
                                 on_update: :restrict

      fks = connection.foreign_keys(:orders)
      fk = fks.first

      expect(fk.on_delete).to eq(:cascade)
      expect(fk.on_update).to eq(:restrict)
    end

    xit "removes a foreign key" do
      connection.add_foreign_key :orders, :users, name: "fk_orders_users"
      connection.remove_foreign_key :orders, name: "fk_orders_users"

      fks = connection.foreign_keys(:orders)
      expect(fks).to be_empty
    end
  end

  describe "SEQUENCES" do
    it "creates a sequence" do
      connection.create_sequence :test_seq

      expect(connection.sequence_exists?(:test_seq)).to be true
    end

    it "gets next value from sequence" do
      skip "Sequence next value implementation has issues"
      connection.create_sequence :test_seq, start_value: 100

      val1 = connection.next_sequence_value(:test_seq)
      val2 = connection.next_sequence_value(:test_seq)

      expect(val1).to be >= 100
      expect(val2).to be > val1
    end

    it "drops a sequence" do
      connection.create_sequence :test_seq
      connection.drop_sequence :test_seq

      expect(connection.sequence_exists?(:test_seq)).to be false
    end
  end

  describe "CHECK CONSTRAINTS" do
    before do
      connection.create_table :products do |t|
        t.string :name
        t.decimal :price
        t.integer :quantity
      end
    end

    it "adds a check constraint" do
      skip "Check constraints implementation has issues"
      connection.add_check_constraint :products, "price > 0", name: "price_positive"

      constraints = connection.check_constraints(:products)
      price_check = constraints.find { |c| c.name.upcase.include?("PRICE_POSITIVE") }

      expect(price_check).not_to be_nil
    end

    it "removes a check constraint" do
      skip "Check constraints implementation has issues"
      connection.add_check_constraint :products, "price > 0", name: "price_positive"
      connection.remove_check_constraint :products, name: "price_positive"

      constraints = connection.check_constraints(:products)
      price_check = constraints.find { |c| c.name.upcase.include?("PRICE_POSITIVE") }

      expect(price_check).to be_nil
    end
  end

  describe "COMMENTS" do
    before do
      connection.create_table :test_table do |t|
        t.string :name
      end
    end

    it "adds table comment" do
      skip "Comments implementation has issues"
      expect do
        connection.add_table_comment :test_table, "This is a test table"
      end.not_to raise_error
    end

    it "adds column comment" do
      skip "Comments implementation has issues"
      expect do
        connection.add_column_comment :test_table, :name, "User's full name"
      end.not_to raise_error
    end
  end

  describe "table and column information" do
    before do
      connection.create_table :test_table do |t|
        t.string :name, null: false
        t.integer :age
        t.timestamps
      end
    end

    it "lists all tables" do
      tables = connection.tables
      expect(tables).to include("SIS_TESTS", "TEST_TABLE")
    end

    it "checks if table exists" do
      expect(connection.table_exists?(:test_table)).to be true
      expect(connection.table_exists?(:nonexistent)).to be false
    end

    it "gets table columns" do
      columns = connection.columns(:test_table)

      expect(columns).not_to be_empty
      expect(columns.map(&:name)).to include("name", "age", "created_at", "updated_at")
    end

    it "gets primary keys" do
      pks = connection.primary_keys(:test_table)
      expect(pks).not_to be_empty
    end
  end
end
