require "spec_helper"

describe 'exception' do
  # Connection is already established in spec_helper.rb before(:suite)
  # No need to re-establish it here - this was causing transaction conflicts

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
