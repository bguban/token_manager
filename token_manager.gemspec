# frozen_string_literal: true

require_relative "lib/token_manager/version"

Gem::Specification.new do |spec|
  spec.name = "token_manager"
  spec.version = TokenManager::VERSION
  spec.authors = ["Bogdan Guban"]
  spec.email = ["biguban@gmail.com"]

  spec.summary = "JWT token manager to organize inter microservice communication"
  spec.description = <<~EOD
    When you have a lot of microservices it can be hard to manage secret keys for all of them. TokenManager
    handles RSA keys generation, caching and verification.
  EOD
  spec.homepage = "https://github.com/bguban"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org/"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
