# frozen_string_literal: true

class TestRecord < ActiveRecord::Base
  self.table_name = "test_records"
  self.primary_key = "id"

  # Define explicit attribute accessors to handle both cases
  def field_varchar
    self[:FIELD_VARCHAR]
  end

  def field_varchar=(value)
    self[:FIELD_VARCHAR] = value
  end

  def field_char
    self[:FIELD_CHAR]
  end

  def field_char=(value)
    self[:FIELD_CHAR] = value
  end

  def field_date
    self[:FIELD_DATE]
  end

  def field_date=(value)
    self[:FIELD_DATE] = value
  end

  def field_smallint
    self[:FIELD_SMALLINT]
  end

  def field_smallint=(value)
    self[:FIELD_SMALLINT] = value
  end

  def field_integer
    self[:FIELD_INTEGER]
  end

  def field_integer=(value)
    self[:FIELD_INTEGER] = value
  end

  def field_double_precision
    self[:FIELD_DOUBLE_PRECISION]
  end

  def field_double_precision=(value)
    self[:FIELD_DOUBLE_PRECISION] = value
  end

  def field_blob_text
    self[:FIELD_BLOB_TEXT]
  end

  def field_blob_text=(value)
    self[:FIELD_BLOB_TEXT] = value
  end

  def field_blob_binary
    self[:FIELD_BLOB_BINARY]
  end

  def field_blob_binary=(value)
    self[:FIELD_BLOB_BINARY] = value
  end

  def field_boolean
    self[:FIELD_BOOLEAN]
  end

  def field_boolean=(value)
    self[:FIELD_BOOLEAN] = value
  end

  def field_decimal
    self[:FIELD_DECIMAL]
  end

  def field_decimal=(value)
    self[:FIELD_DECIMAL] = value
  end
end
