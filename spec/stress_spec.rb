# frozen_string_literal: true

require "spec_helper"
require "concurrent"

RSpec.describe "Stress and performance" do
  before(:all) do
    conn = ActiveRecord::Base.connection
    conn.create_table :stress_writes, force: true, id: :bigint do |t|
      t.string :name
      t.integer :thread
      t.integer :n
    end
  end

  after(:all) do
    conn = ActiveRecord::Base.connection
    conn.drop_table :stress_writes, if_exists: true
  rescue StandardError
    nil
  end

  def stress_model
    Class.new(ActiveRecord::Base) { self.table_name = "stress_writes" }
  end

  describe "concurrent reads" do
    it "dispatches N threads over the pool without race or duplicate rows" do
      m = stress_model
      20.times { |i| m.create!(name: "seed_#{i}", thread: -1, n: i) }

      threads = 8.times.map do |tid|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            results = m.where("n >= ?", 0).order(:n).limit(5).pluck(:name)
            expect(results.length).to eq(5)
            results
          end
        end
      end

      results = threads.map(&:value)
      expect(results.flatten.uniq).to match_array(%w[seed_0 seed_1 seed_2 seed_3 seed_4])
    end
  end

  describe "concurrent writes" do
    it "writes N rows from N threads, all committed and visible" do
      m = stress_model
      m.delete_all

      n_threads = 8
      n_per_thread = 25

      threads = n_threads.times.map do |tid|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            rows = (1..n_per_thread).map { |i| { name: "t#{tid}_#{i}", thread: tid, n: i } }
            m.insert_all!(rows)
          end
        end
      end

      threads.each(&:join)
      expect(m.count).to eq(n_threads * n_per_thread)

      groups = m.group(:thread).count
      n_threads.times { |t| expect(groups[t]).to eq(n_per_thread) }
    end
  end

  describe "pool exhaustion" do
    it "times out when the pool is exhausted" do
      pool = ActiveRecord::Base.connection_pool
      original_size = pool.size
      original_timeout = pool.checkout_timeout
      begin
        ActiveRecord::Base.establish_connection(
          ActiveRecord::Base.connection_db_config.configuration_hash.merge(pool: 1, checkout_timeout: 0.2)
        )
        pool = ActiveRecord::Base.connection_pool
        expect(pool.size).to eq(1)
        expect(pool.checkout_timeout).to eq(0.2)

        held = pool.checkout

        expect {
          pool.with_connection { fail "should not reach" }
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      ensure
        pool.checkin(held) if held
        ActiveRecord::Base.establish_connection(
          ActiveRecord::Base.connection_db_config.configuration_hash.merge(pool: original_size, checkout_timeout: original_timeout)
        )
      end
    end
  end

  describe "isolation across connections" do
    it "does not see uncommitted writes from another connection" do
      m = stress_model
      m.delete_all

      held_conn = ActiveRecord::Base.connection
      pool = ActiveRecord::Base.connection_pool
      other = pool.checkout

      begin
        held_conn.begin_transaction
        m.create!(name: "isolated", thread: -1, n: 0)
        visible = other.select_value("SELECT COUNT(*) FROM stress_writes WHERE name = 'isolated'")
        expect(visible).to eq(0)
      ensure
        held_conn.rollback_transaction
        pool.checkin(other)
      end

      expect(m.where(name: "isolated").count).to eq(0)
    end
  end

  describe "connection reconnect" do
    it "reconnects automatically after disconnect!" do
      conn = ActiveRecord::Base.connection
      conn.disconnect!
      expect(conn).not_to be_active

      v = conn.select_value("SELECT 1 FROM RDB$DATABASE")
      expect(v).to eq(1)
      expect(conn).to be_active
    end

    it "recovers from a broken underlying connection mid-query" do
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT 1 FROM RDB$DATABASE")

      conn.instance_variable_get(:@connection)&.close
      expect(conn).not_to be_active

      v = conn.select_value("SELECT 42 FROM RDB$DATABASE")
      expect(v).to eq(42)
    end
  end

  describe "bulk insert throughput (sanity)" do
    # Firebird limits compiled query contexts per connection (~256).
    # build_insert_sql emits one SELECT FROM RDB$DATABASE per row,
    # so batches above that hit "Too many Contexts of Relation/Procedure/Views".
    # 200 rows stays well under the limit while still exercising the path.
    it "inserts 200 rows in insert_all within a reasonable time" do
      m = stress_model
      m.delete_all

      rows = (1..200).map { |i| { name: "bulk_#{i}", thread: -1, n: i } }
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      m.insert_all!(rows)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

      expect(m.count).to eq(200)
      expect(elapsed).to be < 30
      warn "bulk insert 200 rows: #{(elapsed * 1000).round} ms"
    end
  end

  describe "read throughput (sanity)" do
    it "executes 200 simple queries within reasonable time" do
      conn = ActiveRecord::Base.connection
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      200.times { conn.select_value("SELECT 1 FROM RDB$DATABASE") }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

      expect(elapsed).to be < 30
      warn "200 simple queries: #{(elapsed * 1000).round} ms (#{(elapsed / 200 * 1000).round(2)} ms/q)"
    end
  end
end