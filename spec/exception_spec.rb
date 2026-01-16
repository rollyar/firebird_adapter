require "spec_helper"

describe 'exception' do

  before(:all) do
    @initial_encoding ||= ActiveRecord::Base.connection_db_config.configuration_hash[:encoding] || ActiveRecord::ConnectionAdapters::FirebirdAdapter::DEFAULT_ENCODING
    ActiveRecord::Base.establish_connection(
      adapter:  'firebird',
      database: DB_PATH,
      username: 'sysdba',
      password: 'masterkey',
      encoding: 'UTF8'
    )
  end

  after(:all) do
    ActiveRecord::Base.establish_connection(
      adapter:  'firebird',
      database: DB_PATH,
      username: 'sysdba',
      password: 'masterkey',
      encoding: @initial_encoding
    )
  end

  it 'execute block with exception' do
    expect do
      ActiveRecord::Base.connection.exec_query <<-SQL
        EXECUTE BLOCK
        AS
        BEGIN
          EXCEPTION 'IS A EXCEPTION';
        END
      SQL
    end.to raise_error(Exception, /IS A EXCEPTION/)
  end

end
