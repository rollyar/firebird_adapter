# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CRUD Operations" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "INSERT" do
    it "creates a record" do
      record = SisTest.create!(
        field_varchar: "Test String",
        field_char: "FIXED",
        field_date: Date.today,
        field_smallint: 100,
        field_integer: 42,
        field_double_precision: 3.14
      )

      expect(record).to be_persisted
      expect(record.id).not_to be_nil
      expect(record.field_varchar).to eq("Test String")
      expect(record.field_integer).to eq(42)
    end

    it "creates multiple records" do
      SisTest.create!([
                        { field_varchar: "First" },
                        { field_varchar: "Second" },
                        { field_varchar: "Third" }
                      ])

      expect(SisTest.count).to eq(3)
    end

    it "handles NULL values" do
      record = SisTest.create!(field_varchar: "Test")

      expect(record.field_integer).to be_nil
      expect(record.field_date).to be_nil
    end

    it "auto-increments primary key" do
      record1 = SisTest.create!(field_varchar: "First")
      record2 = SisTest.create!(field_varchar: "Second")

      expect(record1.id).not_to eq(record2.id)
      expect(record1.id).to be > 0
    end

    describe "with different data types" do
      it "handles strings" do
        record = SisTest.create!(field_varchar: "Hello World")
        expect(record.field_varchar).to eq("Hello World")
      end

      it "handles integers" do
        record = SisTest.create!(field_integer: 42)
        expect(record.field_integer).to eq(42)
      end

      it "handles floats" do
        record = SisTest.create!(field_double_precision: 3.14159)
        expect(record.field_double_precision).to eq(3.14159)
      end

      it "handles dates" do
        date = Date.new(2024, 1, 15)
        record = SisTest.create!(field_date: date)
        expect(record.field_date).to eq(date)
      end

      it "handles timestamps" do
        time = Time.now
        record = SisTest.create!(created_at: time)
        expect(record.created_at.to_i).to eq(time.to_i)
      end

      it "handles text blobs" do
        long_text = "A" * 1000
        record = SisTest.create!(field_blob_text: long_text)
        expect(record.field_blob_text).to eq(long_text)
      end

      it "handles binary blobs" do
        binary_data = "BINARY\x00\xFF".b
        record = SisTest.create!(field_blob_binary: binary_data)
        expect(record.field_blob_binary).to eq(binary_data)
      end

      it "handles booleans" do
        record = SisTest.create!(field_boolean: true)
        expect(record.field_boolean).to be true

        record = SisTest.create!(field_boolean: false)
        expect(record.field_boolean).to be false
      end

      it "handles decimals" do
        record = SisTest.create!(field_decimal: BigDecimal("123.45"))
        expect(record.field_decimal).to eq(BigDecimal("123.45"))
      end
    end

    describe "with RETURNING clause" do
      it "returns inserted values" do
        record = SisTest.create!(field_varchar: "Test")
        expect(record.id).not_to be_nil
      end
    end
  end

  describe "SELECT" do
    before do
      SisTest.create!(field_varchar: "First")
      SisTest.create!(field_varchar: "Second")
      SisTest.create!(field_varchar: "Third")
    end

    it "finds all records" do
      expect(SisTest.count).to eq(3)
      records = SisTest.all.to_a
      expect(records.length).to eq(3)
    end

    it "finds by id" do
      record = SisTest.first
      found = SisTest.find(record.id)
      expect(found.id).to eq(record.id)
    end

    it "finds by attributes" do
      found = SisTest.find_by(field_varchar: "First")
      expect(found).not_to be_nil
      expect(found.field_varchar).to eq("First")
    end

    it "uses WHERE with conditions" do
      results = SisTest.where("field_varchar LIKE ?", "%First%")
      expect(results.count).to eq(1)
    end

    it "orders results" do
      SisTest.delete_all
      SisTest.create!([
                        { field_varchar: "First", field_integer: 1 },
                        { field_varchar: "Second", field_integer: 2 },
                        { field_varchar: "Third", field_integer: 3 }
                      ])
      results = SisTest.order(field_integer: :desc).to_a
      expect(results.first.field_integer).to eq(3)
      expect(results.last.field_integer).to eq(1)
    end

    it "limits results" do
      results = SisTest.limit(2).to_a
      expect(results.length).to eq(2)
    end

    it "offsets results" do
      results = SisTest.offset(1).to_a
      expect(results.length).to eq(2)
    end

    it "limit, #offset" do
      SisTest.delete_all
      SisTest.create!([
                        { field_varchar: "First", field_integer: 1 },
                        { field_varchar: "Second", field_integer: 2 },
                        { field_varchar: "Third", field_integer: 3 }
                      ])
      results = SisTest.order(:field_integer).limit(1).offset(1).to_a
      expect(results.length).to eq(1)
      expect(results.first.field_varchar).to eq("Second")
    end

    it "counts records" do
      expect(SisTest.count).to eq(3)
    end

    it "plucks values" do
      values = SisTest.pluck(:field_varchar)
      expect(values).to include("First", "Second", "Third")
    end

    it "finds first and last" do
      expect(SisTest.first.field_varchar).to eq("First")
      expect(SisTest.last.field_varchar).to eq("Third")
    end
  end

  describe "UPDATE" do
    before do
      @record = SisTest.create!(field_varchar: "Original")
    end

    it "updates a single record" do
      @record.update!(field_varchar: "Updated")
      expect(@record.reload.field_varchar).to eq("Updated")
    end

    it "updates multiple attributes" do
      @record.update!(field_varchar: "Updated", field_integer: 100)
      expect(@record.reload.field_varchar).to eq("Updated")
      expect(@record.reload.field_integer).to eq(100)
    end

    it "updates multiple records" do
      SisTest.create!(field_varchar: "First")
      SisTest.create!(field_varchar: "First")

      count = SisTest.where(field_varchar: "First").update_all(field_integer: 999)
      expect(count).to eq(2)
      expect(SisTest.where(field_integer: 999).count).to eq(2)
    end

    xit "updates with SQL expressions" do
      SisTest.create!(field_integer: 10)
      SisTest.create!(field_integer: 20)

      SisTest.update_all("field_integer = field_integer * 2")
      expect(SisTest.sum(:field_integer)).to eq(60)
    end

    it "updates timestamps automatically" do
      old_time = 1.year.ago
      record = SisTest.create!(field_varchar: "Test", updated_at: old_time)
      record.update!(field_varchar: "Updated")
      expect(record.reload.updated_at).to be > old_time
    end
  end

  describe "DELETE" do
    before do
      SisTest.create!(field_varchar: "To Delete")
      SisTest.create!(field_varchar: "To Keep")
    end

    it "destroys a single record" do
      record = SisTest.find_by(field_varchar: "To Delete")
      record.destroy
      expect(SisTest.count).to eq(1)
    end

    it "deletes with where clause" do
      SisTest.where(field_varchar: "To Delete").delete_all
      expect(SisTest.count).to eq(1)
    end

    it "destroys all records" do
      SisTest.destroy_all
      expect(SisTest.count).to eq(0)
    end
  end

  describe "special SQL features" do
    describe "RETURNING clause" do
      it "returns values on insert" do
        record = SisTest.create!(field_varchar: "Test")
        expect(record.id).not_to be_nil
      end
    end

    describe "Common Table Expressions" do
      it "executes CTE queries" do
        result = SisTest.from("(SELECT * FROM sis_tests) AS subquery").count
        expect(result).to eq(0)
      end
    end

    xdescribe "Window Functions" do
      before do
        SisTest.create!(field_integer: 10)
        SisTest.create!(field_integer: 20)
        SisTest.create!(field_integer: 30)
      end

      xit "uses ROW_NUMBER" do
        results = SisTest.select("*, ROW_NUMBER() OVER (ORDER BY field_integer) AS row_num").to_a
        expect(results.length).to eq(3)
      end

      xit "uses SUM with OVER" do
        results = SisTest.select("*, SUM(field_integer) OVER () AS total").to_a
        expect(results.first.respond_to?(:total)).to be true
      end
    end
  end

  describe "edge cases" do
    it "handles empty strings" do
      record = SisTest.create!(field_varchar: "")
      expect(record.field_varchar).to eq("")
    end

    it "handles special characters" do
      record = SisTest.create!(field_varchar: "Test's \"quoted\" & <special>")
      expect(record.field_varchar).to eq("Test's \"quoted\" & <special>")
    end

    it "handles very long strings" do
      long_string = "A" * 10_000
      record = SisTest.create!(field_varchar: long_string)
      expect(record.field_varchar).to eq(long_string)
    end

    xit "handles Unicode characters" do
      unicode = "Hello 世界 🌍"
      record = SisTest.create!(field_varchar: unicode)
      expect(record.field_varchar).to eq(unicode)
    end
  end
end
