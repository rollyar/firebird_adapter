# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Query lifecycle integration" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "preprocess_query is invoked" do
    it "calls preprocess_query for every execute" do
      counter = 0
      original = connection.method(:preprocess_query)
      connection.define_singleton_method(:preprocess_query) do |sql|
        counter += 1
        original.call(sql)
      end

      connection.execute("SELECT 1 FROM RDB$DATABASE")
      connection.execute("SELECT 2 FROM RDB$DATABASE")
      connection.execute("SELECT 3 FROM RDB$DATABASE")

      expect(counter).to eq(3)
    end

    it "calls mark_transaction_written on writes" do
      conn = connection
      conn.create_table :lifecyc_test, force: true, id: :bigint do |t|
        t.string :name
      end
      conn.execute("DELETE FROM lifecyc_test")

      m = Class.new(ActiveRecord::Base) { self.table_name = "lifecyc_test" }

      manager = conn.transaction_manager
      manager.begin_transaction

      begin
        written_before = conn.current_transaction.written
        m.create!(name: "x")
        written_after = conn.current_transaction.written

        expect(written_before).to be_falsey
        expect(written_after).to be(true)
      ensure
        manager.rollback_transaction
      end
    end
  end
end