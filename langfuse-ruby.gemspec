# frozen_string_literal: true

require_relative 'lib/langfuse/version'

Gem::Specification.new do |spec|
  spec.name          = 'langfuse-ruby'
  spec.version       = Langfuse::VERSION
  spec.authors       = ['Richard Sun']
  spec.email         = ['richard.sun@ai-firstly.com']
  spec.summary       = 'Ruby SDK for Langfuse - Open source LLM engineering platform'
  spec.description   = 'Ruby client library for Langfuse, providing tracing, prompt management, ' \
                       'and evaluation capabilities for LLM applications'
  spec.homepage      = 'https://langfuse.com'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = 'https://langfuse.com/docs/sdk/ruby'
  spec.metadata['source_code_uri'] = 'https://github.com/ai-firstly/langfuse-ruby'
  spec.metadata['changelog_uri'] = 'https://github.com/ai-firstly/langfuse-ruby/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://rubydoc.info/gems/langfuse-ruby'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/ai-firstly/langfuse-ruby/issues'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    if File.exist?('.git')
      `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
    else
      Dir.glob('**/*').reject do |f|
        File.directory?(f) ||
          f.match(%r{\A(?:test|spec|features)/}) ||
          f.match(/\A\./) ||
          f.match(/\.gem$/) ||
          f.match(/test_.*\.rb$/)
      end
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_dependency 'concurrent-ruby', '~> 1.0'
  spec.add_dependency 'faraday', '>= 1.8', '< 3.0'
  spec.add_dependency 'faraday-net_http', '>= 1.0', '< 4.0'
  spec.add_dependency 'faraday-multipart', '~> 1.0'
  spec.add_dependency 'json', '~> 2.0'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'vcr', '~> 6.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
  spec.add_development_dependency 'yard', '~> 0.9'
end
