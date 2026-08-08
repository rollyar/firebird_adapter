# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Transactions Edge Cases" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "transaction state recovery" do
    it "allows new transaction after an exception" do
      expect do
        ActiveRecord::Base.transaction do
          SisTest.create!(field_varchar: "tx1")
          raise "boom"
        end
      end.to raise_error(RuntimeError, "boom")

      ActiveRecord::Base.transaction do
        SisTest.create!(field_varchar: "tx2")
      end

      expect(SisTest.where(field_varchar: "tx1").count).to eq(0)
      expect(SisTest.where(field_varchar: "tx2").count).to eq(1)
    end

    it "returns the value of the block on commit" do
      result = ActiveRecord::Base.transaction do
        SisTest.create!(field_varchar: "return_val")
        :ok
      end
      expect(result).to eq(:ok)
    end

    it "returns nil when transaction rolls back" do
      result = ActiveRecord::Base.transaction do
        SisTest.create!(field_varchar: "rb_val")
        raise ActiveRecord::Rollback
      end
      expect(result).to be_nil
    end
  end

  describe "deeply nested savepoints" do
    it "supports nested requires_new savepoints" do
      ActiveRecord::Base.transaction do
        SisTest.create!(field_varchar: "l0")

        ActiveRecord::Base.transaction(requires_new: true) do
          SisTest.create!(field_varchar: "l1")

          ActiveRecord::Base.transaction(requires_new: true) do
            SisTest.create!(field_varchar: "l2")
            raise ActiveRecord::Rollback
          end

          SisTest.create!(field_varchar: "l1_after")
        end

        SisTest.create!(field_varchar: "l0_after")
      end

      %w[l0 l1_after l0_after].each do |v|
        expect(SisTest.where(field_varchar: v).count).to eq(1)
      end
      expect(SisTest.where(field_varchar: "l2").count).to eq(0)
    end
  end

  describe "rollback to savepoint (explicit names)" do
    it "reuses savepoint names without leaking state" do
      connection.transaction do
        SisTest.create!(field_varchar: "reusable_outer")

        connection.create_savepoint("sp1")
        SisTest.create!(field_varchar: "reusable_inner1")
        connection.rollback_to_savepoint("sp1")

        connection.create_savepoint("sp1")
        SisTest.create!(field_varchar: "reusable_inner2")
        connection.release_savepoint("sp1")

        SisTest.create!(field_varchar: "reusable_after")
      end

      expect(SisTest.where(field_varchar: "reusable_outer").count).to eq(1)
      expect(SisTest.where(field_varchar: "reusable_inner1").count).to eq(0)
      expect(SisTest.where(field_varchar: "reusable_inner2").count).to eq(1)
      expect(SisTest.where(field_varchar: "reusable_after").count).to eq(1)
    end
  end

  describe "explicit begin/rollback/commit" do
    it "explicit begin/commit commits work" do
      connection.begin_transaction
      SisTest.create!(field_varchar: "explicit_commit")
      connection.commit_transaction

      expect(SisTest.where(field_varchar: "explicit_commit").count).to eq(1)
    end

    it "explicit begin/rollback discards work" do
      connection.begin_transaction
      SisTest.create!(field_varchar: "explicit_rollback")
      connection.rollback_transaction

      expect(SisTest.where(field_varchar: "explicit_rollback").count).to eq(0)
    end
  end

  describe "isolation" do
    it "keeps uncommitted inserts invisible to a separate connection" do
      pooled = ActiveRecord::Base.connection_pool
      other = pooled.checkout

      begin
        ActiveRecord::Base.transaction do
          SisTest.create!(field_varchar: "iso_uncommitted")
          visible_to_other = other.select_value(<<~SQL)
            SELECT COUNT(*) FROM SIS_TESTS WHERE FIELD_VARCHAR = 'iso_uncommitted'
          SQL
          expect(visible_to_other).to eq(0)
        end

        visible_after = other.select_value(<<~SQL)
          SELECT COUNT(*) FROM SIS_TESTS WHERE FIELD_VARCHAR = 'iso_uncommitted'
        SQL
        expect(visible_after).to eq(1)
      ensure
        pooled.checkin(other)
      end
    end
  end
end
