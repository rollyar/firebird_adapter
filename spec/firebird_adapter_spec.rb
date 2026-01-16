# frozen_string_literal: true

require "spec_helper"


RSpec.describe FirebirdAdapter do
  it "has a version number" do
    expect(FirebirdAdapter::VERSION).not_to be nil
    expect(FirebirdAdapter::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  it "returns the inserted ID" do
    record = SisTest.create!(field_varchar: "Test")
    expect(record.id).to be > 0
    expect(SisTest.find(record.id).id).to eq(record.id)
  end

  it "supports basic ActiveRecord operations with Firebird" do
    # Crear
    record = SisTest.create!(
      field_varchar: "Test",
      field_char: "CHAR12345",
      field_date: Date.today,
      field_smallint: 123,
      field_integer: 456,
      field_double_precision: 3.1416,
      field_blob_text: "Este es un blob de texto largo..."
    )

    expect(record.id).to be_present

    # Leer
    found = SisTest.find(record.id) # o .find(record.id)
    expect(found.field_varchar).to eq("Test")
  end
  #   # Leer
  #   found = TestRecord.find(record.id)
  #   expect(found.name).to eq("Test")
  #   expect(found.value_).to eq(42)

  #   # Actualizar
  #   record.update!(value_: 100)
  #   expect(TestRecord.find(record.id).value_).to eq(100)

  #   # Eliminar
  #   record.destroy!
  #   expect { TestRecord.find(record.id) }.to raise_error(ActiveRecord::RecordNotFound)
  # end
end
