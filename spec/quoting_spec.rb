# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Quoting" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "#quote_column_name" do
    it "quotes column names with special characters" do
      quoted = connection.quote_column_name("column-name")
      # Firebird preserves special chars with quotes but keeps case
      expect(quoted).to include("column-name")
    end

    it "quotes column names with spaces" do
      quoted = connection.quote_column_name("my column")
      # Firebird preserves spaces with quotes
      expect(quoted).to include("my column")
    end

    it "converts simple column names to uppercase" do
      quoted = connection.quote_column_name("id")
      expect(quoted).to eq("ID")
    end

    it "preserves mixed case with quotes" do
      quoted = connection.quote_column_name("myColumn")
      expect(quoted).to eq('"myColumn"')
    end

    it "handles already quoted names" do
      quoted = connection.quote_column_name('"already_quoted"')
      expect(quoted).to eq('"already_quoted"')
    end
  end

  describe "#quote_table_name" do
    it "quotes table names in uppercase" do
      quoted = connection.quote_table_name("users")
      expect(quoted).to eq('"USERS"')
    end

    it "handles already quoted names" do
      quoted = connection.quote_table_name('"Users"')
      expect(quoted).to eq('"Users"')
    end
  end

  describe "#quote_string" do
    it "escapes single quotes" do
      quoted = connection.quote_string("O'Brien")
      expect(quoted).to eq("O''Brien")
    end

    it "handles multiple single quotes" do
      quoted = connection.quote_string("It's a 'test'")
      expect(quoted).to eq("It''s a ''test''")
    end

    it "leaves normal strings unchanged" do
      quoted = connection.quote_string("normal_string")
      expect(quoted).to eq("normal_string")
    end
  end

  describe "#quoted_true and #quoted_false" do
    it "returns TRUE for true values" do
      expect(connection.quoted_true).to eq("TRUE")
    end

    it "returns FALSE for false values" do
      expect(connection.quoted_false).to eq("FALSE")
    end
  end

  describe "#quoted_date" do
    it "formats dates correctly" do
      date = Date.new(2024, 3, 15)
      quoted = connection.quoted_date(date)
      expect(quoted).to include("2024-03-15")
    end

    it "formats timestamps correctly" do
      time = Time.new(2024, 3, 15, 10, 30, 45)
      quoted = connection.quoted_date(time)
      expect(quoted).to include("2024-03-15")
      expect(quoted).to include("10:30:45")
    end
  end

  describe "full query quoting" do
    it "quotes values in WHERE clauses" do
      value = "Test's Value"
      record = SisTest.create!(field_varchar: value)
      found = SisTest.find_by(field_varchar: value)
      expect(found).to eq(record)
    end

    it "handles unicode characters in queries" do
      value = "Café"
      record = SisTest.create!(field_varchar: value)
      found = SisTest.find_by(field_varchar: value)
      expect(found).to eq(record)
    end
  end
end
