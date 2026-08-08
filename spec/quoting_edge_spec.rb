# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Quoting Edge Cases" do
  let(:adapter_class) { ActiveRecord::Base.connection.class }
  let(:connection) { ActiveRecord::Base.connection }

  describe "quote_table_name (class + instance)" do
    it "uppercases lowercase, uppercase, mixed and numeric names" do
      ["users", "USERS", "MyTable", "order_items_2"].each do |name|
        expect(adapter_class.quote_table_name(name)).to eq("\"#{name.upcase}\"")
      end
    end

    it "keeps already-quoted names as-is" do
      expect(adapter_class.quote_table_name(%q{"Users"})).to eq(%q{"Users"})
      expect(connection.quote_table_name(%q{"Users"})).to eq(%q{"Users"})
    end

    it "accepts symbols" do
      expect(adapter_class.quote_table_name(:users)).to eq('"USERS"')
    end

    it "agrees between class and instance methods" do
      ["users", "MyTable", "order_items_2", %q{"x"}].each do |name|
        expect(connection.quote_table_name(name)).to eq(adapter_class.quote_table_name(name))
      end
    end
  end

  describe "quote_column_name consistency" do
    it "matches class and instance methods" do
      ["id", "myColumn", "column-name", "my column", "a1b", "A1", "order"].each do |name|
        expect(connection.quote_column_name(name)).to eq(adapter_class.quote_column_name(name))
      end
    end

    it "uppercases all-simple identifiers" do
      expect(adapter_class.quote_column_name("user_name")).to eq("USER_NAME")
    end

    it "quotes identifiers with underscores and digits but not letters groups" do
      expect(adapter_class.quote_column_name("order2")).to eq("ORDER2")
    end
  end

  describe "round-trip integration" do
    it "quotes special-character identifiers in raw SQL CRUD" do
      connection.create_table :quote_edge_test, force: true do |t|
        t.string :"my column"
        t.string :name
      end

      connection.execute(<<~SQL)
        INSERT INTO "QUOTE_EDGE_TEST" ("my column", NAME) VALUES ('x', 'n')
      SQL

      values = connection.select_value(<<~SQL)
        SELECT "my column" FROM "QUOTE_EDGE_TEST"
      SQL
      expect(values).to eq("x")

      connection.drop_table :quote_edge_test, if_exists: true
    rescue StandardError
      connection.drop_table :quote_edge_test, if_exists: true
      raise
    end

    it "quotes column names in a model with a reserved/simple name" do
      connection.create_table :quote_edge_test, force: true do |t|
        t.string :name
      end

      model = Class.new(ActiveRecord::Base) do
        self.table_name = "quote_edge_test"
      end

      row = model.create!(name: "hello")
      expect(model.find(row.id).name).to eq("hello")

      connection.drop_table :quote_edge_test, if_exists: true
    rescue StandardError
      connection.drop_table :quote_edge_test, if_exists: true
      raise
    end
  end
end