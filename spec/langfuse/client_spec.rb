# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Client do
  let(:client) do
    Langfuse::Client.new(
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com'
    )
  end

  describe '#initialize' do
    it 'initializes with provided credentials' do
      expect(client.public_key).to eq('test_key')
      expect(client.secret_key).to eq('test_secret')
      expect(client.host).to eq('https://test.langfuse.com')
    end

    it 'raises error without public key' do
      expect do
        Langfuse::Client.new(secret_key: 'test_secret')
      end.to raise_error(Langfuse::AuthenticationError, 'Public key is required')
    end

    it 'raises error without secret key' do
      expect do
        Langfuse::Client.new(public_key: 'test_key')
      end.to raise_error(Langfuse::AuthenticationError, 'Secret key is required')
    end
  end

  describe '#trace' do
    it 'creates a new trace' do
      trace = client.trace(name: 'test_trace')

      expect(trace).to be_a(Langfuse::Trace)
      expect(trace.name).to eq('test_trace')
      expect(trace.id).not_to be_nil
    end
  end

  describe '#span' do
    it 'creates a new span' do
      span = client.span(trace_id: 'test_trace_id', name: 'test_span')

      expect(span).to be_a(Langfuse::Span)
      expect(span.name).to eq('test_span')
      expect(span.trace_id).to eq('test_trace_id')
    end
  end

  describe '#generation' do
    it 'creates a new generation' do
      generation = client.generation(
        trace_id: 'test_trace_id',
        name: 'test_generation',
        model: 'gpt-3.5-turbo'
      )

      expect(generation).to be_a(Langfuse::Generation)
      expect(generation.name).to eq('test_generation')
      expect(generation.model).to eq('gpt-3.5-turbo')
    end
  end

  describe '#score' do
    it 'creates a score' do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
                                                                       name: 'test_score',
                                                                       value: 0.8,
                                                                       trace_id: 'test_trace_id'
                                                                     ))

      client.score(
        trace_id: 'test_trace_id',
        name: 'test_score',
        value: 0.8
      )
    end
  end

  describe '#flush' do
    it 'flushes events when queue is not empty' do
      client.instance_variable_set(:@event_queue, [{ id: 'test', type: 'test', body: {} }])

      expect(client).to receive(:post).with('/api/public/ingestion', hash_including(:batch))

      client.flush
    end

    it 'does nothing when queue is empty' do
      client.instance_variable_set(:@event_queue, [])

      expect(client).not_to receive(:post)

      client.flush
    end
  end

  describe 'auto_flush configuration' do
    it 'enables auto_flush by default' do
      client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret'
      )

      expect(client.auto_flush).to be true
      expect(client.instance_variable_get(:@flush_thread)).not_to be_nil
    end

    it 'disables auto_flush when explicitly set to false' do
      client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        auto_flush: false
      )

      expect(client.auto_flush).to be false
      expect(client.instance_variable_get(:@flush_thread)).to be_nil
    end

    it 'respects global configuration for auto_flush' do
      Langfuse.configure do |config|
        config.auto_flush = false
      end

      client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret'
      )

      expect(client.auto_flush).to be false
      expect(client.instance_variable_get(:@flush_thread)).to be_nil

      # Reset configuration
      Langfuse.configure do |config|
        config.auto_flush = true
      end
    end

    it 'respects environment variable for auto_flush' do
      ENV['LANGFUSE_AUTO_FLUSH'] = 'false'

      client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret'
      )

      expect(client.auto_flush).to be false
      expect(client.instance_variable_get(:@flush_thread)).to be_nil

      ENV.delete('LANGFUSE_AUTO_FLUSH')
    end

    it 'parameter overrides environment variable' do
      ENV['LANGFUSE_AUTO_FLUSH'] = 'false'

      client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        auto_flush: true
      )

      expect(client.auto_flush).to be true
      expect(client.instance_variable_get(:@flush_thread)).not_to be_nil

      ENV.delete('LANGFUSE_AUTO_FLUSH')
    end
  end

  describe '#shutdown' do
    it 'kills flush thread when auto_flush is enabled' do
      client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        auto_flush: true
      )

      flush_thread = client.instance_variable_get(:@flush_thread)
      expect(flush_thread).to receive(:kill)

      client.shutdown
    end

    it 'does not kill flush thread when auto_flush is disabled' do
      client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        auto_flush: false
      )

      expect(client.instance_variable_get(:@flush_thread)).to be_nil

      # Should not raise any errors
      expect { client.shutdown }.not_to raise_error
    end
  end

  describe 'ingestion_mode configuration' do
    it 'defaults to legacy mode' do
      expect(client.ingestion_mode).to eq(:legacy)
    end

    it 'accepts otel mode via constructor' do
      otel_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        ingestion_mode: :otel,
        auto_flush: false
      )

      expect(otel_client.ingestion_mode).to eq(:otel)
    end

    it 'respects environment variable LANGFUSE_INGESTION_MODE' do
      ENV['LANGFUSE_INGESTION_MODE'] = 'otel'

      otel_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false
      )

      expect(otel_client.ingestion_mode).to eq(:otel)

      ENV.delete('LANGFUSE_INGESTION_MODE')
    end

    it 'respects global configuration for ingestion_mode' do
      Langfuse.configure do |config|
        config.ingestion_mode = :otel
      end

      otel_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false
      )

      expect(otel_client.ingestion_mode).to eq(:otel)

      Langfuse.configure do |config|
        config.ingestion_mode = :legacy
      end
    end

    it 'creates otel_exporter when in otel mode' do
      otel_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        ingestion_mode: :otel,
        auto_flush: false
      )

      expect(otel_client.instance_variable_get(:@otel_exporter)).to be_a(Langfuse::OtelExporter)
      expect(otel_client.instance_variable_get(:@otel_connection)).not_to be_nil
    end

    it 'does not create otel_exporter in legacy mode' do
      expect(client.instance_variable_get(:@otel_exporter)).to be_nil
      expect(client.instance_variable_get(:@otel_connection)).to be_nil
    end
  end

  describe '#flush with OTEL mode' do
    let(:otel_client) do
      Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        ingestion_mode: :otel,
        auto_flush: false
      )
    end

    it 'sends events via OTEL exporter' do
      stub_request(:post, 'https://test.langfuse.com/api/public/otel/v1/traces')
        .to_return(
          status: 200,
          body: '{}',
          headers: { 'Content-Type' => 'application/json' }
        )

      otel_client.trace(name: 'otel-test')
      otel_client.flush

      expect(WebMock).to have_requested(:post, 'https://test.langfuse.com/api/public/otel/v1/traces')
    end

    it 'includes x-langfuse-ingestion-version header' do
      stub_request(:post, 'https://test.langfuse.com/api/public/otel/v1/traces')
        .with(headers: { 'x-langfuse-ingestion-version' => '4' })
        .to_return(
          status: 200,
          body: '{}',
          headers: { 'Content-Type' => 'application/json' }
        )

      otel_client.trace(name: 'otel-header-test')
      otel_client.flush

      expect(WebMock).to have_requested(:post, 'https://test.langfuse.com/api/public/otel/v1/traces')
        .with(headers: { 'x-langfuse-ingestion-version' => '4' })
    end
  end

  describe '#get_prompt' do
    it 'URL-encodes prompt names with special characters' do
      # Stub the HTTP request with WebMock
      stub_request(:get, 'https://test.langfuse.com/api/public/v2/prompts/EXEMPLE%2Fmy-prompt')
        .to_return(
          status: 200,
          body: {
            id: 'test-id',
            name: 'EXEMPLE/my-prompt',
            version: 1,
            prompt: 'test prompt',
            type: 'text'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      prompt = client.get_prompt('EXEMPLE/my-prompt')
      expect(prompt).to be_a(Langfuse::Prompt)
      expect(prompt.name).to eq('EXEMPLE/my-prompt')
    end

    it 'URL-encodes prompt names with spaces' do
      stub_request(:get, 'https://test.langfuse.com/api/public/v2/prompts/my%20prompt')
        .to_return(
          status: 200,
          body: {
            id: 'test-id',
            name: 'my prompt',
            version: 1,
            prompt: 'test prompt',
            type: 'text'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      prompt = client.get_prompt('my prompt')
      expect(prompt).to be_a(Langfuse::Prompt)
      expect(prompt.name).to eq('my prompt')
    end

    it 'URL-encodes prompt names with multiple special characters' do
      stub_request(:get, 'https://test.langfuse.com/api/public/v2/prompts/test%2Fprompt%20name%3Fquery')
        .to_return(
          status: 200,
          body: {
            id: 'test-id',
            name: 'test/prompt name?query',
            version: 1,
            prompt: 'test prompt',
            type: 'text'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      prompt = client.get_prompt('test/prompt name?query')
      expect(prompt).to be_a(Langfuse::Prompt)
      expect(prompt.name).to eq('test/prompt name?query')
    end

    it 'handles simple prompt names without special characters' do
      stub_request(:get, 'https://test.langfuse.com/api/public/v2/prompts/simple-prompt')
        .to_return(
          status: 200,
          body: {
            id: 'test-id',
            name: 'simple-prompt',
            version: 1,
            prompt: 'test prompt',
            type: 'text'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      prompt = client.get_prompt('simple-prompt')
      expect(prompt).to be_a(Langfuse::Prompt)
      expect(prompt.name).to eq('simple-prompt')
    end
  end
end
