# frozen_string_literal: true

require 'bundler/setup'
require_relative '../lib/langfuse'
require 'webmock/rspec'
require 'vcr'

# Load support files
Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Include support modules
  config.include OfflineModeHelper

  # Clean up after each test
  config.after(:each) do
    # Clean up any test clients to prevent background thread issues
    if defined?(client) && client.respond_to?(:shutdown)
      begin
        client.shutdown
      rescue StandardError
        # Ignore shutdown errors in tests
      end
    end
  end
end

VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
end

WebMock.disable_net_connect!(allow_localhost: true)
