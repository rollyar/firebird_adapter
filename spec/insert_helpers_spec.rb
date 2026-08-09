# frozen_string_literal: true

require "spec_helper"

# Unit tests for the private split_values_rows / split_commas / values_to_select
# helpers used by build_plain_insert_sql. These document the contract:
#
#   split_values_rows splits a VALUES tuple-list into individual tuple strings,
#   respecting parenthesis depth, string literals, and escaped quotes.
#   split_commas splits a single tuple (a, b, c) into its parts.
#   values_to_select rewrites a VALUES list as a UNION ALL of SELECT ... FROM
#   RDB$DATABASE rows (Firebird cannot do multi-row INSERT VALUES).
#
# We reach the private methods via send. If the helpers are renamed, these
# tests will need to be updated; the names are stable in the current adapter.

RSpec.describe "Bulk insert helpers (private)" do
  let(:conn) { ActiveRecord::Base.connection }

  def call(name, *args)
    conn.send(name, *args)
  end

  describe "split_values_rows" do
    it "splits simple tuples on top-level commas" do
      out = call(:split_values_rows, "(1, 'a'), (2, 'b'), (3, 'c')")
      expect(out).to eq(["1, 'a'", "2, 'b'", "3, 'c'"])
    end

    it "ignores commas inside parentheses" do
      out = call(:split_values_rows, "(ARRAY[1,2,3], 'x'), (ARRAY[4,5], 'y')")
      expect(out).to eq(["ARRAY[1,2,3], 'x'", "ARRAY[4,5], 'y'"])
    end

    it "ignores commas inside single-quoted strings" do
      out = call(:split_values_rows, "('a, b, c'), ('d, e')")
      expect(out).to eq(["'a, b, c'", "'d, e'"])
    end

    it "respects doubled single quotes inside strings" do
      out = call(:split_values_rows, "('it''s, ok'), ('fine')")
      expect(out).to eq(["'it''s, ok'", "'fine'"])
    end

    it "ignores commas inside nested function calls" do
      out = call(:split_values_rows, "(COALESCE(a, b), 1), (COALESCE(c, d), 2)")
      expect(out).to eq(["COALESCE(a, b), 1", "COALESCE(c, d), 2"])
    end

    it "handles a single tuple" do
      out = call(:split_values_rows, "(1, 'a')")
      expect(out).to eq(["1, 'a'"])
    end

    it "strips the wrapping parentheses of each row" do
      out = call(:split_values_rows, "(1), (2), (3)")
      expect(out).to eq(["1", "2", "3"])
    end
  end

  describe "split_commas" do
    it "splits simple comma-separated values" do
      expect(call(:split_commas, "1, 'a', 2.0")).to eq(["1", "'a'", "2.0"])
    end

    it "ignores commas inside strings and parens" do
      expect(call(:split_commas, "ARRAY[1,2], 'a, b', FOO(1,2)")).to eq(
        ["ARRAY[1,2]", "'a, b'", "FOO(1,2)"]
      )
    end

    it "respects doubled quotes" do
      expect(call(:split_commas, "'it''s', 'fine'")).to eq(["'it''s'", "'fine'"])
    end
  end

  describe "values_to_select" do
    it "rewrites a VALUES list as UNION ALL of SELECT … FROM RDB$DATABASE" do
      sql = call(:values_to_select, "VALUES (1, 'a'), (2, 'b')")
      expected = "SELECT 1, 'a' FROM RDB$DATABASE UNION ALL SELECT 2, 'b' FROM RDB$DATABASE"
      expect(sql).to eq(expected)
    end

    it "aliases columns when provided" do
      sql = call(:values_to_select, "VALUES (1, 'a'), (2, 'b')", %w[N V])
      expected = "SELECT 1 AS N, 'a' AS V FROM RDB$DATABASE UNION ALL SELECT 2 AS N, 'b' AS V FROM RDB$DATABASE"
      expect(sql).to eq(expected)
    end

    it "preserves commas and parens in values" do
      sql = call(:values_to_select, "VALUES (ARRAY[1,2], 'x'), (ARRAY[3,4], 'y')")
      expected = "SELECT ARRAY[1,2], 'x' FROM RDB$DATABASE UNION ALL SELECT ARRAY[3,4], 'y' FROM RDB$DATABASE"
      expect(sql).to eq(expected)
    end

    it "strips a leading VALUES keyword" do
      sql = call(:values_to_select, "VALUES (1)")
      expect(sql).to eq("SELECT 1 FROM RDB$DATABASE")
    end
  end

  describe "integration: build_plain_insert_sql" do
    it "emits a single INSERT with a UNION ALL source for multi-row VALUES" do
      insert = double(
        skip_duplicates?: false,
        update_duplicates?: false,
        into: 'INTO "WIDGETS" (NAME, QTY)',
        values_list: "(1, 'a'), (2, 'b')",
        returning: nil
      )

      sql = call(:build_plain_insert_sql, insert)
      expect(sql).to start_with('INSERT INTO "WIDGETS" (NAME, QTY) SELECT ')
      expect(sql).to include("UNION ALL")
      expect(sql).not_to include("VALUES")
    end
  end
end
