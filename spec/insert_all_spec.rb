# frozen_string_literal: true

require "spec_helper"

RSpec.describe "insert_all / upsert_all" do
  before(:all) do
    conn = ActiveRecord::Base.connection
    conn.create_table :bulk_insert_items, force: true, id: :bigint do |t|
      t.string :name, null: false
      t.integer :age
    end
    conn.add_index :bulk_insert_items, :name, unique: true
  end

  after(:all) do
    conn = ActiveRecord::Base.connection
    conn.disconnect!
    conn = ActiveRecord::Base.connection
    conn.drop_table :bulk_insert_items, if_exists: true
  rescue StandardError
    nil
  end

  before(:each) do
    conn = ActiveRecord::Base.connection
    conn.execute("DELETE FROM bulk_insert_items") if conn.table_exists?(:bulk_insert_items)
  end

  def bulk_model
    Class.new(ActiveRecord::Base) do
      self.table_name = "bulk_insert_items"
    end
  end

  describe "#insert_all!" do
    it "inserts multiple rows" do
      model = bulk_model
      model.insert_all!([
                          { name: "a", age: 1 },
                          { name: "b", age: 2 }
                        ])

      expect(model.count).to eq(2)
      expect(model.order(:id).pluck(:name)).to eq(%w[a b])
    end

    it "inserts a single row" do
      model = bulk_model
      model.insert_all!([{ name: "c", age: 3 }])

      expect(model.count).to eq(1)
      expect(model.first.name).to eq("c")
    end

    it "raises on duplicate unique values" do
      model = bulk_model
      model.insert_all!([{ name: "a", age: 1 }])

      expect {
        model.insert_all!([{ name: "a", age: 2 }])
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#insert_all" do
    it "skips rows that would violate a unique constraint" do
      model = bulk_model
      model.insert_all!([{ name: "a", age: 1 }])

      model.insert_all([{ name: "a", age: 99 }, { name: "z", age: 0 }], unique_by: :name)

      expect(model.count).to eq(2)
      expect(model.find_by(name: "a").age).to eq(1)
      expect(model.find_by(name: "z").age).to eq(0)
    end

    it "inserts without a unique_by when no duplicates are present" do
      model = bulk_model
      model.insert_all([{ name: "a", age: 1 }, { name: "b", age: 2 }])

      expect(model.count).to eq(2)
    end
  end

  describe "#upsert_all" do
    it "updates existing rows and inserts new ones" do
      model = bulk_model
      model.insert_all!([{ name: "a", age: 1 }, { name: "b", age: 2 }])

      model.upsert_all([{ name: "b", age: 50 }, { name: "c", age: 3 }], unique_by: :name)

      expect(model.count).to eq(3)
      expect(model.find_by(name: "a").age).to eq(1)
      expect(model.find_by(name: "b").age).to eq(50)
      expect(model.find_by(name: "c").age).to eq(3)
    end

    it "upserts by primary key when present in attributes" do
      model = bulk_model
      first = model.create!(name: "x", age: 1)

      model.upsert_all([{ id: first.id, name: "x", age: 99 }])

      expect(model.count).to eq(1)
      expect(model.find(first.id).age).to eq(99)
    end
  end

  describe "RETURNING behavior" do
    it "returns nothing for multi-row inserts (Firebird cannot multi-row RETURNING)" do
      model = bulk_model

      result = model.insert_all!([{ name: "p", age: 1 }, { name: "q", age: 2 }])

      expect(result).to be_a(ActiveRecord::Result)
      expect(model.count).to eq(2)
    end
  end
end
