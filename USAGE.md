# Firebird Adapter Usage Guide

## Overview

The Firebird Adapter provides ActiveRecord support for Firebird databases (2.5+, 3.0+, 4.0+). This guide shows how to use it effectively.

## Basic Configuration

### Standard Connection (SYSDBA)

```ruby
# config/database.yml
production:
  adapter: firebird
  database: /path/to/your/database.fdb
  username: SYSDBA
  password: masterkey
  charset: UTF8
  downcase: true  # Normalizes column names to lowercase
```



## Features

### Supported Features
- ✅ Basic CRUD operations
- ✅ Migrations
- ✅ Primary keys with IDENTITY columns
- ✅ Transactions and savepoints
- ✅ Foreign keys
- ✅ Various data types (VARCHAR, CHAR, DATE, INTEGER, BLOB, etc.)
- ✅ Multiple Firebird versions (3.0, 4.0, 5.0+)
- ✅ Connection pooling
- ✅ Case-insensitive column name handling

### Firebird 4.0+ Features
- ✅ BOOLEAN data type
- ✅ Time zone support
- ✅ DECFLOAT
- ✅ Enhanced security

### Firebird 5.0+ Features  
- ✅ SKIP LOCKED support
- ✅ Partial indexes
- ✅ INT128 support

## Migration Examples

```ruby
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :name, limit: 100
      t.string :email, limit: 255
      t.text :bio
      t.boolean :active
      t.timestamps
    end
    
    add_index :users, :email, unique: true
  end
end
```

## Model Usage

```ruby
class User < ActiveRecord::Base
  # Table and column names are automatically normalized to lowercase
  # when downcase: true is set in connection config
  
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
end

# Basic CRUD
user = User.create(name: "John Doe", email: "john@example.com")
users = User.where(active: true).order(:name)
user.update(name: "Jane Doe")
user.destroy
```

## Data Type Mapping

| Rails Type | Firebird Type | Notes |
|------------|--------------|-------|
| string | VARCHAR | Default limit: 255 |
| text | BLOB SUB_TYPE TEXT | |
| integer | INTEGER | |
| bigint | BIGINT | |
| float | FLOAT | |
| decimal | DECIMAL | |
| boolean | BOOLEAN | Firebird 3.0+ |
| date | DATE | |
| datetime | TIMESTAMP | |
| binary | BLOB SUB_TYPE BINARY | |
| uuid | CHAR(16) CHARACTER SET OCTETS | |

## Testing with Docker

```bash
# Start Firebird containers
docker compose up -d firebird3 firebird4 firebird5

# Run tests
docker compose run gem_development bundle exec rspec

# Run specific test
docker compose run gem_development bundle exec rspec spec/crud_operations_spec.rb
```

## Troubleshooting

### Common Issues

1. **"Column does not belong to referenced table"**
   - Check that column names match between model and database
   - Verify `downcase: true` in database config

2. **"Unknown attribute" errors**
   - Ensure table exists and columns are properly defined
   - Check primary key configuration

3. **Connection issues**
   - Verify Firebird service is running
   - Check database path permissions
   - Validate user credentials

### Debug Mode

Add debug logging to your configuration:

```ruby
# In environment.rb or initializer
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = Logger::DEBUG
```

## Performance Tips

1. **Use connection pooling** - Configure appropriate pool size
2. **Optimize queries** - Use specific column selections instead of SELECT *
3. **Index strategically** - Add indexes on frequently queried columns
4. **Batch operations** - Use insert_all for bulk inserts when possible

## Security Considerations

1. **Never use SYSDBA in production** - Create appropriate users with minimal permissions
2. **Use roles** - Group permissions into roles for easier management
3. **Encrypt connections** - Use SSL when connecting remotely
4. **Regular backups** - Implement automated backup strategies

## Getting Help

- Check the test suite: `bundle exec rspec`
- Review migration logs for detailed information
- Enable debug logging for troubleshooting
- Check Firebird server logs for connection issues