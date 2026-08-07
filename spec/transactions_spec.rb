# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Transactions" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "basic transactions" do
    it "commits changes" do
      ActiveRecord::Base.transaction do
        SisTest.create!(field_varchar: "commit_test")
      end

      count = SisTest.where(field_varchar: "commit_test").count
      expect(count).to eq(1)
    end

    it "rolls back changes on error" do
      ActiveRecord::Base.transaction do
        SisTest.create!(field_varchar: "rollback_test")
        raise ActiveRecord::Rollback
      end

      count = SisTest.where(field_varchar: "rollback_test").count
      expect(count).to eq(0)
    end

    it "rolls back on exception" do
      expect do
        ActiveRecord::Base.transaction do
          SisTest.create!(field_varchar: "exception_test")
          raise StandardError, "something went wrong"
        end
      end.to raise_error(StandardError)

      count = SisTest.where(field_varchar: "exception_test").count
      expect(count).to eq(0)
    end
  end

  describe "nested transactions (savepoints)" do
    it "rolls back inner savepoint with requires_new" do
      ActiveRecord::Base.transaction do
        r1 = SisTest.create!(field_varchar: "outer")

        ActiveRecord::Base.transaction(requires_new: true) do
          r2 = SisTest.create!(field_varchar: "inner")
          raise ActiveRecord::Rollback
        end

        r3 = SisTest.create!(field_varchar: "after_rollback")
      end

      expect(SisTest.where(field_varchar: "inner").count).to eq(0)
      expect(SisTest.where(field_varchar: "after_rollback").count).to eq(1)
    end

    it "commits outer transaction after inner savepoint rollback" do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.transaction(requires_new: true) do
          SisTest.create!(field_varchar: "inner_only")
          raise ActiveRecord::Rollback
        end

        SisTest.create!(field_varchar: "outer_only")
      end

      expect(SisTest.where(field_varchar: "inner_only").count).to eq(0)
      expect(SisTest.where(field_varchar: "outer_only").count).to eq(1)
    end

    it "rolls back outer transaction with exception from inner savepoint" do
      expect do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.transaction(requires_new: true) do
            SisTest.create!(field_varchar: "savepoint_data")
            raise StandardError, "critical error"
          end
        end
      end.to raise_error(StandardError)

      expect(SisTest.where(field_varchar: "savepoint_data").count).to eq(0)
    end

    it "does not rollback outer on Rollback without requires_new (Rails behavior)" do
      ActiveRecord::Base.transaction do
        SisTest.create!(field_varchar: "a")

        ActiveRecord::Base.transaction do
          SisTest.create!(field_varchar: "b")
          raise ActiveRecord::Rollback
        end
      end

      expect(SisTest.where(field_varchar: "a").count).to eq(1)
      expect(SisTest.where(field_varchar: "b").count).to eq(1)
    end

    it "supports manual savepoints via SQL" do
      connection = ActiveRecord::Base.connection
      connection.execute("DELETE FROM sis_tests")

      connection.transaction do
        SisTest.create!(field_varchar: "before_sp")

        connection.create_savepoint("custom_sp")
        SisTest.create!(field_varchar: "during_sp")
        connection.rollback_to_savepoint("custom_sp")

        SisTest.create!(field_varchar: "after_rollback")
      end

      expect(SisTest.where(field_varchar: "before_sp").count).to eq(1)
      expect(SisTest.where(field_varchar: "during_sp").count).to eq(0)
      expect(SisTest.where(field_varchar: "after_rollback").count).to eq(1)
    end
  end

  describe "affected_rows" do
    before do
      SisTest.create!(field_varchar: "row1")
      SisTest.create!(field_varchar: "row2")
      SisTest.create!(field_varchar: "row3")
    end

    it "exec_update returns affected rows count" do
      count = SisTest.where(field_varchar: ["row1", "row2", "row3"]).update_all(field_integer: 99)
      expect(count).to eq(3)
    end

    it "exec_delete returns affected rows count" do
      count = SisTest.where(field_varchar: "row1").delete_all
      expect(count).to eq(1)
    end

    it "update_all with partial match" do
      count = SisTest.where(field_varchar: "row1").update_all(field_integer: 10)
      expect(count).to eq(1)

      row = SisTest.find_by(field_varchar: "row1")
      expect(row.field_integer).to eq(10)
    end

    it "delete_all removes correct records" do
      SisTest.where(field_varchar: ["row1", "row2"]).delete_all
      expect(SisTest.count).to eq(1)
      expect(SisTest.first.field_varchar).to eq("row3")
    end
  end
end