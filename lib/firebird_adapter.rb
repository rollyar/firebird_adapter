# frozen_string_literal: true

require "active_support/lazy_load_hooks"
require "firebird_adapter/version"

# Let Rails load ActiveRecord first, then load our adapter
ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters.register("firebird", "ActiveRecord::ConnectionAdapters::FirebirdAdapter",
                                            "active_record/connection_adapters/firebird_adapter")
end
