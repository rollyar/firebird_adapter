# frozen_string_literal: true

module ActiveRecord
  module ConnectionHandling
    def firebird_connection(config)
      require "active_record/connection_adapters/firebird/adapter"

      ConnectionAdapters::FirebirdAdapter.new(config)
    end
  end
end
