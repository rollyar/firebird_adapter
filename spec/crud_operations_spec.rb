# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CRUD Operations" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "INSERT" do
    it "creates a record" do
      # Debug: check what columns exist
      columns = SisTest.columns
      puts "Available columns: #{columns.map(&:name).join(", ")}"
      puts "Primary key: #{SisTest.primary_key}"
      puts "Column details:"
      columns.each do |col|
        puts "  #{col.name}: #{col.sql_type} (primary: #{col.name == SisTest.primary_key}, auto_populated: #{ActiveRecord::Base.connection.return_value_after_insert?(col)})"
      end

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
      r1 = SisTest.create!(field_varchar: "First")
      r2 = SisTest.create!(field_varchar: "Second")

      expect(r2.id).to be > r1.id
    end

    context "with different data types" do
      it "handles strings" do
        record = SisTest.create!(
          field_varchar: "Variable length",
          field_char: "Fixed"
        )

        expect(record.field_varchar).to eq("Variable length")
        expect(record.field_char.strip).to eq("Fixed")
      end

      it "handles integers" do
        record = SisTest.create!(
          field_smallint: 32_767,
          field_integer: 2_147_483_647
        )

        expect(record.field_smallint).to eq(32_767)
        expect(record.field_integer).to eq(2_147_483_647)
      end

      it "handles floats" do
        record = SisTest.create!(field_double_precision: 3.14159)

        expect(record.field_double_precision).to be_within(0.00001).of(3.14159)
      end

      it "handles dates" do
        date = Date.new(2024, 1, 15)
        record = SisTest.create!(field_date: date)

        expect(record.field_date).to eq(date)
      end

      it "handles timestamps" do
        time = Time.new(2024, 1, 15, 10, 30, 0)
        record = SisTest.create!(created_at: time)

        expect(record.created_at).to be_within(1.second).of(time)
      end

      it "handles text blobs" do
        long_text = "Lorem ipsum " * 1000
        record = SisTest.create!(field_blob_text: long_text)

        expect(record.field_blob_text).to eq(long_text)
      end

      it "handles binary blobs" do
        binary_data = "\x00\x01\x02\xFF" * 100
        record = SisTest.create!(field_blob_binary: binary_data)

        expect(record.field_blob_binary).to eq(binary_data)
      end

      it "handles booleans" do
        record = SisTest.create!(field_boolean: true)
        expect(record.field_boolean).to be true

        record2 = SisTest.create!(field_boolean: false)
        expect(record2.field_boolean).to be false
      end

      it "handles decimals" do
        record = SisTest.create!(field_decimal: BigDecimal("123.45"))
        expect(record.field_decimal).to eq(BigDecimal("123.45"))
      end
    end

    context "with RETURNING clause" do
      it "returns inserted values" do
        record = SisTest.create!(field_varchar: "Test")

        expect(record.id).not_to be_nil
        expect(record.created_at).not_to be_nil
      end
    end
  end

  describe "SELECT" do
    before do
      5.times do |i|
        SisTest.create!(
          field_varchar: "Record #{i}",
          field_integer: i * 10
        )
      end
    end

    it "finds all records" do
      records = SisTest.all.to_a
      expect(records.size).to eq(5)
    end

    it "finds by id" do
      record = SisTest.first
      found = SisTest.find(record.id)

      expect(found).to eq(record)
    end

    it "finds by attributes" do
      records = SisTest.where(field_varchar: "Record 2").to_a
      expect(records.size).to eq(1)
      expect(records.first.field_varchar).to eq("Record 2")
    end

    it "uses WHERE with conditions" do
      records = SisTest.where("field_integer > ?", 20).to_a
      expect(records.size).to eq(2)
    end

    it "orders results" do
      records = SisTest.order(field_integer: :desc).to_a
      expect(records.first.field_integer).to eq(40)
      expect(records.last.field_integer).to eq(0)
    end

    it "limits results" do
      records = SisTest.limit(3).to_a
      expect(records.size).to eq(3)
    end

    it "offsets results" do
      records = SisTest.order(:id).offset(2).to_a
      expect(records.size).to eq(3)
    end

    it "counts records" do
      expect(SisTest.count).to eq(5)
    end

    it "plucks values" do
      values = SisTest.order(:field_integer).pluck(:field_integer)
      expect(values).to eq([0, 10, 20, 30, 40])
    end

    it "finds first and last" do
      first = SisTest.order(:id).first
      last = SisTest.order(:id).last

      expect(first.id).to be < last.id
    end
  end

  describe "UPDATE" do
    let!(:record) { SisTest.create!(field_varchar: "Original") }

    it "updates a single record" do
      record.update!(field_varchar: "Updated")

      expect(record.field_varchar).to eq("Updated")
      expect(SisTest.find(record.id).field_varchar).to eq("Updated")
    end

    it "updates multiple attributes" do
      record.update!(
        field_varchar: "New String",
        field_integer: 999
      )

      reloaded = SisTest.find(record.id)
      expect(reloaded.field_varchar).to eq("New String")
      expect(reloaded.field_integer).to eq(999)
    end

    it "updates multiple records" do
      SisTest.create!([
                        { field_varchar: "Test1" },
                        { field_varchar: "Test2" }
                      ])

      SisTest.where(field_varchar: %w[Test1 Test2]).update_all(field_integer: 100)

      expect(SisTest.where(field_integer: 100).count).to eq(2)
    end

    it "updates with SQL expressions" do
      record.update!(field_integer: 10)

      SisTest.where(id: record.id).update_all("field_integer = field_integer + 5")

      expect(SisTest.find(record.id).field_integer).to eq(15)
    end

    it "updates timestamps automatically" do
      created = record.created_at
      sleep 0.1

      record.update!(field_varchar: "Changed")

      expect(record.updated_at).to be > created
    end
  end

  describe "DELETE" do
    let!(:record) { SisTest.create!(field_varchar: "To Delete") }

    it "destroys a single record" do
      expect do
        record.destroy
      end.to change(SisTest, :count).by(-1)

      expect(SisTest.find_by(id: record.id)).to be_nil
    end

    it "deletes with where clause" do
      SisTest.create!([
                        { field_varchar: "Keep" },
                        { field_varchar: "Delete1" },
                        { field_varchar: "Delete2" }
                      ])

      SisTest.where(field_varchar: %w[Delete1 Delete2]).delete_all

      expect(SisTest.where(field_varchar: "Keep").count).to eq(1)
      expect(SisTest.count).to eq(2)
    end

    it "destroys all records" do
      SisTest.create!([
                        { field_varchar: "Test1" },
                        { field_varchar: "Test2" }
                      ])

      SisTest.destroy_all

      expect(SisTest.count).to eq(0)
    end
  end

  describe "special SQL features" do
    context "RETURNING clause" do
      it "returns values on insert" do
        record = SisTest.create!(field_varchar: "Test")

        # El ID debe ser devuelto automáticamente
        expect(record.id).not_to be_nil
      end
    end

    context "Common Table Expressions" do
      it "executes CTE queries" do
        5.times { |i| SisTest.create!(field_integer: i) }

        sql = <<~SQL
          WITH numbered AS (
            SELECT
              field_integer,
              ROW_NUMBER() OVER (ORDER BY field_integer) as rn
            FROM SIS_TESTS
          )
          SELECT field_integer FROM numbered WHERE rn <= 3
        SQL

        result = connection.select_all(sql)
        expect(result.length).to eq(3)
      end
    end

    context "Window Functions" do
      it "uses ROW_NUMBER" do
        5.times { |i| SisTest.create!(field_integer: i * 10) }

        sql = <<~SQL
          SELECT
            field_integer,
            ROW_NUMBER() OVER (ORDER BY field_integer DESC) as rank
          FROM SIS_TESTS
        SQL

        result = connection.select_all(sql)
        expect(result.first["rank"]).to eq(1)
        expect(result.first["field_integer"]).to eq(40)
      end

      it "uses SUM with OVER" do
        [10, 20, 30].each { |val| SisTest.create!(field_integer: val) }

        sql = <<~SQL
          SELECT
            field_integer,
            SUM(field_integer) OVER (
              ORDER BY id
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) as running_total
          FROM SIS_TESTS
          ORDER BY id
        SQL

        result = connection.select_all(sql)
        expect(result.last["running_total"]).to eq(60)
      end
    end
  end

  describe "edge cases" do
    it "handles empty strings" do
      record = SisTest.create!(field_varchar: "")
      expect(record.field_varchar).to eq("")
    end

    it "handles special characters" do
      special = "Test's \"quoted\" text & symbols <>"
      record = SisTest.create!(field_varchar: special)
      expect(record.field_varchar).to eq(special)
    end

    it "handles very long strings" do
      long_string = "a" * 10_000
      record = SisTest.create!(field_blob_text: long_string)
      expect(record.field_blob_text.length).to eq(10_000)
    end

    it "handles Unicode characters" do
      unicode = "Testeo con ñ, á, é, í, ó, ú 中文 العربية"
      record = SisTest.create!(field_varchar: unicode)
      expect(record.field_varchar).to eq(unicode)
    end
  end
end
