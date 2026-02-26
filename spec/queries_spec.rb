require "spec_helper"

RSpec.describe "query" do
  before do
    SisTest.delete_all
    SisTest.create!(field_integer: 1)
    SisTest.create!(field_integer: 2)
    SisTest.create!(field_integer: 3)
    SisTest.create!(field_integer: 4)
    SisTest.create!(field_integer: 5)
  end

  it "#first" do
    expect(SisTest.first.field_integer).to eq(1)
  end

  it "#second" do
    expect(SisTest.second.field_integer).to eq(2)
  end

  it "#third" do
    expect(SisTest.third.field_integer).to eq(3)
  end

  it "#fourth" do
    expect(SisTest.fourth.field_integer).to eq(4)
  end

  it "#fifth" do
    expect(SisTest.fifth.field_integer).to eq(5)
  end

  it "#all" do
    expect(SisTest.all.count).to eq(5)
  end

  it "#limit" do
    expect(SisTest.limit(2).count).to eq(2)
  end

  it "#offset" do
    expect(SisTest.offset(3).count).to eq(2)
  end

  it "#limit, #offset" do
    expect(SisTest.limit(1).offset(2).first.field_integer).to eq(3)
  end

  it "#where" do
    expect(SisTest.where(field_integer: 3).count).to eq(1)
  end

  it "where with accent" do
    value = "A1áéíóúàç"
    SisTest.create!(field_varchar: value)
    expect(SisTest.where(field_varchar: value).count).to eq(1)
  end

  it "where search is larger than field size" do
    long_value = "A" * 300
    SisTest.create!(field_varchar: long_value[0...255])
    expect(SisTest.where("field_varchar = ?", long_value[0...255]).count).to eq(1)
  end
end
