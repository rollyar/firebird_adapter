require "spec_helper"

describe "field types" do
  it "varchar" do
    value = "UN VALOR VARCHAR"
    record = SisTest.create!(field_varchar: value).reload
    expect(record.field_varchar).to eq value
  end

  it "char" do
    value = "UN VALOR"
    record = SisTest.create!(field_char: value).reload
    expect(record.field_char.strip).to eq value
  end

  it "date" do
    date = Date.today
    record = SisTest.create!(field_date: date).reload
    expect(record.field_date).to eq date
  end

  it "smallint" do
    record = SisTest.create!(field_smallint: "1").reload
    expect(record.field_smallint).to eq 1
  end

  it "integer" do
    record = SisTest.create!(field_integer: "1").reload
    expect(record.field_integer).to eq 1
  end

  it "double precision" do
    record = SisTest.create!(field_double_precision: "99.99").reload
    expect(record.field_double_precision).to eq 99.99
  end

  it "blob text" do
    value = "UN VALOR TEXT"
    record = SisTest.create!(field_blob_text: value).reload
    expect(record.field_blob_text.force_encoding("UTF-8")).to eq value
  end

  it "blob binary" do
    value = "binary value"
    record = SisTest.create!(field_blob_binary: value).reload
    expect(record.field_blob_binary).to eq value
  end
end
