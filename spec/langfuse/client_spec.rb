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

  describe 'initialization' do
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
  end

  describe 'trace operations' do
    it 'creates a new trace' do
      trace = client.trace(name: 'test_trace')

      expect(trace).to be_a(Langfuse::Trace)
      expect(trace.name).to eq('test_trace')
      expect(trace.id).not_to be_nil
    end

    it 'creates a trace with detailed attributes' do
      trace = client.trace(
        name: 'detailed-trace',
        user_id: 'user-123',
        session_id: 'session-456',
        input: { query: 'test query' },
        output: { result: 'test result' },
        environment: 'test',
        metadata: { version: '1.0', tags: %w[test demo] }
      )

      expect(trace.name).to eq('detailed-trace')
      expect(trace.user_id).to eq('user-123')
      expect(trace.session_id).to eq('session-456')
      expect(trace.input).to eq({ query: 'test query' })
      expect(trace.output).to eq({ result: 'test result' })
      expect(trace.metadata[:version]).to eq('1.0')
      expect(trace.metadata[:tags]).to eq(%w[test demo])
      expect(trace.metadata[:environment]).to eq('test')
    end

    it 'creates a trace with complex nested data' do
      complex_input = {
        user_query: 'Explain quantum computing',
        context: {
          user_level: 'beginner',
          preferred_language: 'English',
          time_constraint: '5 minutes'
        },
        constraints: {
          max_complexity: 'medium',
          avoid_mathematics: true
        }
      }

      trace = client.trace(name: 'complex-trace', input: complex_input)

      expect(trace.input).to eq(complex_input)
      expect(trace.input[:context][:user_level]).to eq('beginner')
    end
  end

  describe 'span operations' do
    it 'creates a new span' do
      span = client.span(trace_id: 'test_trace_id', name: 'test_span')

      expect(span).to be_a(Langfuse::Span)
      expect(span.name).to eq('test_span')
      expect(span.trace_id).to eq('test_trace_id')
    end
  end

  describe 'generation operations' do
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

  describe 'scoring operations' do
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

    it 'creates a score with optional parameters' do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
                                                                       name: 'detailed-score',
                                                                       value: 'excellent',
                                                                       data_type: 'CATEGORICAL',
                                                                       config_id: 'quality-v1',
                                                                       trace_id: 'test-trace',
                                                                       observation_id: 'obs-123'
                                                                     ))

      client.score(
        trace_id: 'test-trace',
        name: 'detailed-score',
        value: 'excellent',
        data_type: 'CATEGORICAL',
        config_id: 'quality-v1',
        observation_id: 'obs-123'
      )
    end
  end

  describe 'event management' do
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
  end

  describe 'auto_flush behavior' do
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
  end

  describe 'global configuration for auto_flush' do
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
  end

  describe 'environment variable for auto_flush' do
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

  describe 'event queue operations' do
    let(:test_client) { Langfuse::Client.new(public_key: 'test_key', secret_key: 'test_secret', debug: false) }

    it 'initializes with empty event queue' do
      queue = test_client.instance_variable_get(:@event_queue)
      expect(queue).to be_empty
    end

    it 'queues events from various operations' do
      # Create some operations that should queue events
      trace = test_client.trace(name: 'queue-test-trace')
      span = trace.span(name: 'queue-test-span')
      generation = span.generation(name: 'queue-test-gen', model: 'test-model')

      # Check that events were queued
      queue = test_client.instance_variable_get(:@event_queue)
      expect(queue.length).to be > 0

      # Verify event types
      event_types = queue.map { |event| event[:type] }
      expect(event_types).to include('trace-create', 'span-create', 'generation-create')
    end

    it 'queues score events' do
      trace = test_client.trace(name: 'score-test-trace')

      # Add scores at different levels
      trace.score(name: 'trace-score', value: 0.8)

      # Check queue has score events
      queue = test_client.instance_variable_get(:@event_queue)
      score_events = queue.select { |event| event[:type] == 'score-create' }
      expect(score_events.length).to be > 0
    end

    it 'handles event queue with concurrent access' do
      # Create multiple traces concurrently
      threads = []
      5.times do |i|
        threads << Thread.new do
          test_client.trace(name: "concurrent-trace-#{i}")
        end
      end

      threads.each(&:join)

      queue = test_client.instance_variable_get(:@event_queue)
      expect(queue.length).to eq(5) # 5 trace-create events
    end

    it 'clears queue after successful flush' do
      # Add some events
      test_client.trace(name: 'flush-test')
      queue = test_client.instance_variable_get(:@event_queue)
      expect(queue.length).to be > 0

      # Mock successful flush
      allow(test_client).to receive(:post).and_return({ success: true })

      test_client.flush

      # Queue should be empty after flush
      expect(queue).to be_empty
    end
  end

  describe 'configuration options' do
    it 'accepts custom configuration options' do
      custom_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://custom.langfuse.com',
        debug: true,
        timeout: 60,
        retries: 5,
        auto_flush: false
      )

      expect(custom_client.host).to eq('https://custom.langfuse.com')
      expect(custom_client.debug).to be true
      expect(custom_client.timeout).to eq(60)
      expect(custom_client.retries).to eq(5)
      expect(custom_client.auto_flush).to be false
    end

    it 'handles debug mode configuration' do
      debug_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        debug: true
      )

      expect(debug_client.debug).to be true
    end

    it 'uses default configuration when options not provided' do
      default_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret'
      )

      expect(default_client.host).to eq('https://us.cloud.langfuse.com')
      expect(default_client.timeout).to eq(30)
      expect(default_client.retries).to eq(3)
      expect(default_client.auto_flush).to be true
    end
  end

  describe 'error handling and edge cases' do
    it 'handles large input data' do
      large_input = { data: 'x' * 10_000 } # 10KB string
      trace = client.trace(name: 'large-input-test', input: large_input)

      expect(trace.input[:data].length).to eq(10_000)
    end

    it 'handles Unicode characters' do
      unicode_input = { message: 'Hello 世界! 🌍 Test with émojis' }
      trace = client.trace(name: 'unicode-test', input: unicode_input)

      expect(trace.input[:message]).to include('世界')
      expect(trace.input[:message]).to include('🌍')
    end

    it 'handles special characters in metadata' do
      special_metadata = {
        'special-chars' => '!@#$%^&*()_+-=[]{}|;:,.<>?',
        'unicode' => 'Café München — Тест',
        'quotes' => '"Single" and \'double\' quotes',
        'newlines' => "Line 1\nLine 2\tTabbed"
      }
      trace = client.trace(name: 'special-chars-test', metadata: special_metadata)

      expect(trace.metadata['unicode']).to include('Café München')
      expect(trace.metadata['quotes']).to include('"Single"')
    end
  end
end
