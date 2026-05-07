# FirebirdAdapter

ActiveRecord Firebird Adapter for Rails 8.1+ with modern Firebird support.

## 🚀 Rails 8.1+ Compatibility

This version provides **full Rails 8.1+ compatibility** with support for:
- ✅ Ruby 3.3.6+
- ✅ ActiveRecord 8.1+
- ✅ Firebird 3.0, 4.0, 5.0
- ✅ Modern Firebird types (BOOLEAN, DECFLOAT, TIME WITH TZ)
- ✅ IDENTITY columns
- ✅ Enhanced migrations and schema operations

## 📋 Requirements

- **Ruby**: >= 3.3.6
- **Rails**: >= 8.1.0
- **Firebird**: 3.0.11+ (4.0.5+ and 5.0.1+ recommended for full features)
- **fb gem**: ~> 0.10.0

## 🛠️ Quick Start

### 1. Add to Gemfile

```ruby
gem 'firebird_adapter', '~> 8.1'
```

### 2. Configure Database

Create `config/database.yml`:

```yaml
development:
  adapter: firebird
  database: /path/to/your/database.fdb
  host: localhost
  port: 3050
  username: SYSDBA
  password: masterkey
  charset: UTF8
  role: READ_WRITE  # Optional

test:
  adapter: firebird
  database: /path/to/test_database.fdb
  host: localhost
  port: 3050
  username: SYSDBA
  password: masterkey
  charset: UTF8

production:
  adapter: firebird
  database: /path/to/production_database.fdb
  host: your-firebird-server
  port: 3050
  username: your_user
  password: your_password
  charset: UTF8
  role: READ_WRITE
```

### 3. Install and Setup

```bash
bundle install
rails db:create
rails db:migrate
```

## 🐳 Docker Development

Use Docker Compose for easy local development:

```bash
# Start Firebird containers
docker-compose up -d firebird3 firebird4 firebird5

# Run tests
docker-compose run --rm gem_development bundle exec rspec

# Stop containers
docker-compose down
```

## 🔧 Supported Features

### Modern Firebird Types
- **BOOLEAN** (Firebird 3.0+)
- **DECFLOAT** (Firebird 4.0+) - Decimal floating point
- **TIME WITH TIME ZONE** (Firebird 4.0+)
- **TIMESTAMP WITH TIME ZONE** (Firebird 4.0+)
- **IDENTITY columns** (Firebird 3.0+)
- **INT128** (Firebird 4.0+)

### Rails Features
- ✅ Migrations with all Rails 7.2+ features
- ✅ Foreign key constraints
- ✅ Check constraints
- ✅ Index management (including partial indexes)
- ✅ Schema introspection
- ✅ Prepared statements
- ✅ Query explain plans
- ✅ Transaction isolation levels
- ✅ Savepoints
- ✅ Connection pooling

### Advanced Features
- ✅ Role-based access control
- ✅ User management
- ✅ Wire encryption support
- ✅ Multiple database connections
- ✅ Database cleanup and maintenance

## 📊 Version Matrix

| Firebird Version | Ruby | Rails | Status |
|------------------|------|-------|---------|
| 3.0.11+ | 3.3.6+ | 8.1+ | ✅ Supported |
| 4.0.5+ | 3.3.6+ | 8.1+ | ✅ Recommended |
| 5.0.1+ | 3.3.6+ | 8.1+ | ✅ Latest |

## 🧪 Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test suites
bundle exec rspec spec/types_test.rb
bundle exec rspec spec/adapter_spec.rb
bundle exec rspec spec/identity_test.rb

# Run with coverage
bundle exec rspec --format documentation
```

## 🔍 Troubleshooting

### Common Issues

**"generator not defined" error:**
- Ensure you're using IDENTITY columns for primary keys
- Check that `supports_identity_columns?` returns true

**Connection issues:**
- Verify Firebird service is running
- Check database path and permissions
- Ensure correct port (default: 3050)

**Type conversion issues:**
- BOOLEAN values are properly converted
- DECFLOAT precision is handled correctly
- Time zone types work with Rails timezone support

### Debug Mode

Enable debug output:

```ruby
# In your environment files
config.log_level = :debug

# Or in console
ActiveRecord::Base.logger.level = Logger::DEBUG
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 Development

```bash
# Clone the repository
git clone https://github.com/rollyar/firebird_adapter.git
cd firebird_adapter

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Build gem
gem build firebird_adapter.gemspec

# Install locally
gem install ./firebird_adapter-8.1.0.gem
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE.txt](LICENSE.txt) file for details.

## 🙏 Acknowledgments

- Original Firebird adapter maintainers
- Firebird SQL community
- Rails core team for adapter patterns
- All contributors and users

## 📞 Support

- 📧 Issues: [GitHub Issues](https://github.com/rollyar/firebird_adapter/issues)
- 📖 Documentation: [Wiki](https://github.com/rollyar/firebird_adapter/wiki)
- 💬 Discussions: [GitHub Discussions](https://github.com/rollyar/firebird_adapter/discussions)

---

**Note**: This adapter is specifically designed for Rails 7.2+ and modern Firebird features. For older Rails versions, please use the appropriate branch.


## Installation

Add in your Gemfile:

```ruby
gem 'firebird_adapter', '8.1'
```


And then execute:

    $ bundle

## Usage

Configure your database.yml:

```ruby
development:
  adapter: firebird
  host: localhost
  database: db/development.fdb
  username: SYSDBA
  password: masterkey
  encoding: UTF-8
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
