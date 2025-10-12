# frozen_string_literal: true

RSpec.describe Langfuse do
  describe 'version' do
    it 'has a version number' do
      expect(Langfuse::VERSION).not_to be nil
    end
  end

  describe 'configuration' do
    describe '.configure' do
      it 'allows configuration' do
        Langfuse.configure do |config|
          config.public_key = 'test_key'
          config.secret_key = 'test_secret'
          config.host = 'https://test.langfuse.com'
        end

        expect(Langfuse.configuration.public_key).to eq('test_key')
        expect(Langfuse.configuration.secret_key).to eq('test_secret')
        expect(Langfuse.configuration.host).to eq('https://test.langfuse.com')
      end
    end
  end

  describe 'client creation' do
    describe '.new' do
      it 'creates a new client instance' do
        client = Langfuse.new(
          public_key: 'test_key',
          secret_key: 'test_secret'
        )

        expect(client).to be_a(Langfuse::Client)
        expect(client.public_key).to eq('test_key')
        expect(client.secret_key).to eq('test_secret')
      end

      it 'creates client with all options' do
        client = Langfuse.new(
          public_key: 'test_public',
          secret_key: 'test_secret',
          host: 'https://custom.langfuse.com',
          debug: true,
          timeout: 60,
          retries: 5,
          auto_flush: false
        )

        expect(client.public_key).to eq('test_public')
        expect(client.secret_key).to eq('test_secret')
        expect(client.host).to eq('https://custom.langfuse.com')
        expect(client.debug).to be true
        expect(client.timeout).to eq(60)
        expect(client.retries).to eq(5)
        expect(client.auto_flush).to be false
      end
    end
  end

  describe 'environment variable support' do
    around do |example|
      # Store original env vars
      original_env = {}
      %w[LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY LANGFUSE_HOST LANGFUSE_DEBUG].each do |var|
        original_env[var] = ENV[var]
      end

      example.run

      # Restore original env vars
      original_env.each do |var, value|
        ENV[var] = value
      end
    end

    it 'uses environment variables when no explicit configuration provided' do
      ENV['LANGFUSE_PUBLIC_KEY'] = 'env_public_key'
      ENV['LANGFUSE_SECRET_KEY'] = 'env_secret_key'
      ENV['LANGFUSE_HOST'] = 'https://env.langfuse.com'
      ENV['LANGFUSE_DEBUG'] = 'true'

      # Reset configuration to clean state
      Langfuse.instance_variable_set(:@configuration, nil)

      client = Langfuse.new

      expect(client.public_key).to eq('env_public_key')
      expect(client.secret_key).to eq('env_secret_key')
      expect(client.host).to eq('https://env.langfuse.com')
      expect(client.debug).to be true
    end

    it 'prioritizes explicit parameters over environment variables' do
      ENV['LANGFUSE_PUBLIC_KEY'] = 'env_public_key'
      ENV['LANGFUSE_SECRET_KEY'] = 'env_secret_key'

      client = Langfuse.new(
        public_key: 'explicit_public_key',
        secret_key: 'explicit_secret_key'
      )

      expect(client.public_key).to eq('explicit_public_key')
      expect(client.secret_key).to eq('explicit_secret_key')
    end
  end
end
