# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SQL injection hardening" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "schema introspection with quoted names" do
    it "does not crash when name contains a single quote (would-be SQL injection)" do
      quoted_name = "weird'table"
      # table_exists?, view_exists?, indexes, primary_keys, foreign_keys,
      # sequence_exists? return empty/false when the table does not exist.
      expect(connection.table_exists?(quoted_name)).to be(false)
      expect(connection.view_exists?(quoted_name)).to be(false)
      expect(connection.indexes(quoted_name)).to eq([])
      expect(connection.primary_keys(quoted_name)).to eq([])
      expect(connection.foreign_keys(quoted_name)).to eq([])
      expect(connection.sequence_exists?(quoted_name)).to be(false)
    end

    it "column_definitions raises StatementInvalid for missing table with quote" do
      expect {
        connection.column_definitions("ghost'table")
      }.to raise_error(ActiveRecord::StatementInvalid, /does not exist/)
    end
  end

  describe "firebird_version" do
    it "raises ConnectionNotEstablished when the version probe fails" do
      conn = ActiveRecord::Base.connection
      original = conn.method(:query_value)
      conn.instance_variable_set(:@firebird_version, nil)
      begin
        conn.define_singleton_method(:query_value) { |*_a| raise Fb::Error, "synthetic" }
        expect { conn.firebird_version }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      ensure
        conn.singleton_class.send(:remove_method, :query_value)
        conn.define_singleton_method(:query_value) { |*a| original.call(*a) }
        conn.instance_variable_set(:@firebird_version, nil)
        conn.firebird_version # warm cache for following tests
      end
    end
  end

  describe "auto_incremented? regression" do
    it "does not flag a non-identity BIGINT primary key as auto_incremented" do
      conn = ActiveRecord::Base.connection
      conn.drop_table :audit_no_inc, if_exists: true
      conn.execute(<<~SQL)
        CREATE TABLE AUDIT_NO_INC (
          ID BIGINT NOT NULL PRIMARY KEY,
          NAME VARCHAR(255)
        )
      SQL

      col = conn.columns("audit_no_inc").find { |c| c.name == "id" }
      expect(col).not_to be_nil
      expect(col.auto_incremented?).to be(false)
    ensure
      conn.drop_table :audit_no_inc, if_exists: true
    end

    it "flags IDENTITY BIGINT primary key as auto_incremented" do
      conn = ActiveRecord::Base.connection
      conn.create_table :audit_with_inc, force: true, id: :primary_key do |t|
        t.string :name
      end
      col = conn.columns("audit_with_inc").find { |c| c.name == "id" }
      expect(col.auto_incremented?).to be(true)
    ensure
      conn.drop_table :audit_with_inc, if_exists: true
    end
  end

  describe "rename_table errors" do
    it "raises the original error class, not NotImplementedError" do
      conn = ActiveRecord::Base.connection
      expect {
        conn.rename_table(:definitely_not_a_table, :whatever)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "create_sequence / drop_sequence" do
    it "raises on drop of a non-existent sequence (no longer silenced)" do
      conn = ActiveRecord::Base.connection
      expect {
        conn.drop_sequence(:definitely_not_a_sequence)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "drops an existing sequence" do
      conn = ActiveRecord::Base.connection
      conn.create_sequence(:audit_hardening_seq)
      expect(conn.sequence_exists?(:audit_hardening_seq)).to be(true)
      conn.drop_sequence(:audit_hardening_seq)
      expect(conn.sequence_exists?(:audit_hardening_seq)).to be(false)
    end
  end
end