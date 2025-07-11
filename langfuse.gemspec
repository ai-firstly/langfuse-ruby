require_relative 'lib/langfuse/version'

Gem::Specification.new do |spec|
  spec.name          = "langfuse"
  spec.version       = Langfuse::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]
  spec.summary       = "Ruby SDK for Langfuse - Open source LLM engineering platform"
  spec.description   = "Ruby client library for Langfuse, providing tracing, prompt management, and evaluation capabilities for LLM applications"
  spec.homepage      = "https://github.com/your-username/langfuse-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/your-username/langfuse-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/your-username/langfuse-ruby/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    if File.exist?('.git')
      `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
    else
      Dir.glob('**/*').reject { |f|
        File.directory?(f) ||
        f.match(%r{\A(?:test|spec|features)/}) ||
        f.match(%r{\A\.}) ||
        f.match(%r{\.gem$}) ||
        f.match(%r{test_.*\.rb$})
      }
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-net_http", "~> 3.0"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "concurrent-ruby", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "yard", "~> 0.9"
end
