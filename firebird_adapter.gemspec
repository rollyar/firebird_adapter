lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require_relative "lib/firebird_adapter/version"

Gem::Specification.new do |spec|
  spec.name          = "firebird_adapter"
  spec.version       = FirebirdAdapter::VERSION
  spec.authors       = ["F\u00E1bio Rodrigues", "Rolando Arnaudo", "EmilioEduardoDb"]
  spec.email         = ["fabio.info@gmail.com"]
  spec.homepage      = "https://github.com/FabioMR/firebird_adapter"
  spec.summary       = "ActiveRecord adapter for Firebird"
  spec.description   = "Enables Rails applications to connect to Firebird databases."
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.3.6"

  spec.files = Dir["lib/**/*"]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "fb", "~> 0.10.0"
  spec.add_development_dependency "bundler", ">= 2.5.2"
  spec.add_development_dependency "database_cleaner", ">= 2.1"
  spec.add_development_dependency "pry-meta", ">= 0.0.10"
  spec.add_dependency "activerecord", ">= 7.2.0", "< 8.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
