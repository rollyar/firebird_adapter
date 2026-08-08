# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Exception translation edge cases" do
  before(:all) do
    conn = ActiveRecord::Base.connection
    conn.create_table :ex_parents, force: true, id: :bigint do |t|
      t.string :code, null: false
    end
    conn.add_index :ex_parents, :code, unique: true
    conn.create_table :ex_children, force: true, id: :bigint do |t|
      t.bigint :ex_parent_id
      t.string :code, null: false
    end
    conn.add_foreign_key :ex_children, :ex_parents
    conn.add_index :ex_children, :code, unique: true
  end

  after(:all) do
    conn = ActiveRecord::Base.connection
    conn.drop_table :ex_children, if_exists: true
    conn.drop_table :ex_parents, if_exists: true
  rescue StandardError
    nil
  end

  def parent_model
    Class.new(ActiveRecord::Base) { self.table_name = "ex_parents" }
  end

  def child_model
    Class.new(ActiveRecord::Base) { self.table_name = "ex_children" }
  end

  it "maps unique violations to RecordNotUnique" do
    p = parent_model
    p.create!(code: "ex_dup")

    expect {
      p.create!(code: "ex_dup")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "maps foreign key violations to InvalidForeignKey" do
    ch = child_model

    expect {
      ch.create!(ex_parent_id: 9_999_999, code: "ex_fk")
    }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "leaves not-null violations as StatementInvalid" do
    p = parent_model
    parent = p.create!(code: "ex_null")
    ch = child_model

    expect {
      ch.create!(ex_parent_id: parent.id, code: nil)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "maps FK violations on DELETE to InvalidForeignKey" do
    p = parent_model
    ch = child_model
    parent = p.create!(code: "ex_del")
    ch.create!(ex_parent_id: parent.id, code: "ex_del_c")

    expect {
      ActiveRecord::Base.connection.execute(<<~SQL)
        DELETE FROM ex_parents WHERE id = #{parent.id}
      SQL
    }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end