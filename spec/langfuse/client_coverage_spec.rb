# frozen_string_literal: true

require 'stringio'

require_relative '../spec_helper'

RSpec.describe Langfuse::Client do
  # retries: 0 keeps the failure-path examples from waiting for the retry backoff;
  # retrying behaviour has its own describe block below.
  let(:client) do
    Langfuse::Client.new(
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com',
      auto_flush: false,
      retries: 0
    )
  end

  let(:debug_client) do
    Langfuse::Client.new(
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com',
      auto_flush: false,
      debug: true
    )
  end

  describe '#create_prompt' do
    it 'posts to /api/public/v2/prompts and returns a Prompt' do
      stub_request(:post, 'https://test.langfuse.com/api/public/v2/prompts')
        .to_return(
          status: 200,
          body: {
            id: 'prompt-1',
            name: 'my-prompt',
            version: 1,
            prompt: 'Hello {{name}}',
            type: 'text'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      prompt = client.create_prompt(name: 'my-prompt', prompt: 'Hello {{name}}')

      expect(prompt).to be_a(Langfuse::Prompt)
      expect(prompt.name).to eq('my-prompt')
      expect(prompt.prompt).to eq('Hello {{name}}')
      expect(WebMock).to have_requested(:post, 'https://test.langfuse.com/api/public/v2/prompts')
    end
  end

  describe '#get_prompt caching' do
    let(:prompt_body) do
      {
        id: 'prompt-1',
        name: 'cached-prompt',
        version: 1,
        prompt: 'Hello',
        type: 'text'
      }.to_json
    end

    before do
      stub_request(:get, 'https://test.langfuse.com/api/public/v2/prompts/cached-prompt')
        .to_return(
          status: 200,
          body: prompt_body,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'uses cache on second call (no additional HTTP request)' do
      prompt1 = client.get_prompt('cached-prompt')
      prompt2 = client.get_prompt('cached-prompt')

      expect(prompt1.name).to eq('cached-prompt')
      expect(prompt2.name).to eq('cached-prompt')
      expect(WebMock).to have_requested(:get, 'https://test.langfuse.com/api/public/v2/prompts/cached-prompt').once
    end

    it 'refetches after cache expiry' do
      client.get_prompt('cached-prompt')

      # A zero TTL means every entry is already stale by the time it is read.
      client.get_prompt('cached-prompt', cache_ttl_seconds: 0)

      expect(WebMock).to have_requested(:get, 'https://test.langfuse.com/api/public/v2/prompts/cached-prompt').twice
    end
  end

  describe '#get_prompt with HTML response' do
    it 'raises APIError when response body is HTML' do
      stub_request(:get, 'https://test.langfuse.com/api/public/v2/prompts/bad-prompt')
        .to_return(
          status: 200,
          body: '<!DOCTYPE html><html><body>Not Found</body></html>',
          headers: { 'Content-Type' => 'text/html' }
        )

      expect do
        client.get_prompt('bad-prompt')
      end.to raise_error(Langfuse::APIError, /Received HTML response instead of JSON/)
    end
  end

  describe '#get_prompt stale fallback' do
    let(:log_output) { StringIO.new }
    let(:client) do
      Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        retries: 0,
        logger: Logger.new(log_output)
      )
    end
    let(:prompt_body) do
      {
        id: 'prompt-1',
        name: 'flaky-prompt',
        version: 1,
        prompt: 'Hello',
        type: 'text'
      }.to_json
    end
    let(:prompt_url) { 'https://test.langfuse.com/api/public/v2/prompts/flaky-prompt' }

    it 'serves the expired cache entry when the refetch fails' do
      stub_request(:get, prompt_url)
        .to_return(status: 200, body: prompt_body, headers: { 'Content-Type' => 'application/json' })
      prompt = client.get_prompt('flaky-prompt')

      stub_request(:get, prompt_url).to_return(status: 500, body: '{}')

      stale = client.get_prompt('flaky-prompt', cache_ttl_seconds: 0)
      expect(stale).to be(prompt)
      expect(log_output.string).to include('serving the cached copy')
    end

    it 'raises when there is no cached copy to fall back to' do
      stub_request(:get, prompt_url).to_return(status: 500, body: '{}')

      expect { client.get_prompt('flaky-prompt') }.to raise_error(Langfuse::APIError)
    end
  end

  describe 'event queue bound' do
    it 'drops the oldest events once max_queue_size is reached' do
      log_output = StringIO.new
      capped = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        max_queue_size: 3,
        logger: Logger.new(log_output),
        shutdown_on_exit: false
      )

      5.times { |i| capped.trace(id: "trace-#{i}", name: 't') }

      queued_ids = capped.instance_variable_get(:@event_queue).map { |event| event[:body]['id'] }
      expect(queued_ids).to eq(%w[trace-2 trace-3 trace-4])
      expect(log_output.string).to include('dropped 1 oldest events')
    end
  end

  describe 'flush failure handling' do
    it 'drops events after a permanent failure (4xx validation error)' do
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 422, body: '{}', headers: { 'Content-Type' => 'application/json' })
      client.trace(id: 'trace-1', name: 't')

      expect { client.flush }.to raise_error(Langfuse::ValidationError)
      expect(client.instance_variable_get(:@event_queue)).to be_empty
    end

    it 're-queues events after a transient failure (5xx)' do
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 500, body: '{}', headers: { 'Content-Type' => 'application/json' })
      client.trace(id: 'trace-1', name: 't')

      expect { client.flush }.to raise_error(Langfuse::APIError)
      expect(client.instance_variable_get(:@event_queue).length).to eq(1)
    end
  end

  describe 'fork safety' do
    it 'drops inherited events and recreates the flush thread in the child process' do
      # shutdown (in ensure) flushes the remaining event
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{"successes":[],"errors":[]}',
                   headers: { 'Content-Type' => 'application/json' })
      forked = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: true,
        flush_interval: 3600,
        shutdown_on_exit: false
      )
      original_thread = forked.instance_variable_get(:@flush_thread)
      inherited = [{ id: 'inherited', type: 'trace-create', timestamp: 'now', body: { 'id' => 'old' } }]
      forked.instance_variable_set(:@event_queue, Concurrent::Array.new(inherited))

      allow(Process).to receive(:pid).and_return(999_999)
      forked.trace(id: 'child-trace', name: 't')

      queued_ids = forked.instance_variable_get(:@event_queue).map { |event| event[:body]['id'] }
      expect(queued_ids).to eq(['child-trace'])
      new_thread = forked.instance_variable_get(:@flush_thread)
      expect(new_thread).not_to eq(original_thread)
      expect(new_thread).to be_alive
    ensure
      original_thread&.kill
      forked&.shutdown
    end
  end

  describe '#inspect' do
    it 'redacts the secret key' do
      inspected = client.inspect

      expect(inspected).to include('test_key')
      expect(inspected).not_to include('test_secret')
    end
  end

  describe '#enqueue_event' do
    it 'skips invalid event types in debug mode' do
      expect do
        debug_client.enqueue_event('invalid-type', { id: '123' })
      end.to output(/Warning: Invalid event type/).to_stdout

      queue = debug_client.instance_variable_get(:@event_queue)
      expect(queue).to be_empty
    end

    it 'skips invalid event types silently in non-debug mode' do
      client.enqueue_event('invalid-type', { id: '123' })

      queue = client.instance_variable_get(:@event_queue)
      expect(queue).to be_empty
    end

    it 'merges trace-update into existing trace-create' do
      client.enqueue_event('trace-create', { id: 'trace-1', name: 'original' })
      client.enqueue_event('trace-update', { id: 'trace-1', name: 'updated', output: 'result' })

      queue = client.instance_variable_get(:@event_queue)
      expect(queue.length).to eq(1)
      expect(queue[0][:type]).to eq('trace-create')
      expect(queue[0][:body]['name']).to eq('updated')
      expect(queue[0][:body]['output']).to eq('result')
    end

    it 'keeps fields from the queued trace-create when a partial update merges into it' do
      trace = client.trace(id: 'trace-1', name: 'original', input: 'question')
      trace.update(output: 'answer')

      queue = client.instance_variable_get(:@event_queue)
      expect(queue.length).to eq(1)
      expect(queue[0][:body]).to include('name' => 'original', 'input' => 'question', 'output' => 'answer')
    end

    it 'converts trace-update to trace-create when no matching trace-create exists' do
      client.enqueue_event('trace-update', { id: 'trace-new', name: 'converted' })

      queue = client.instance_variable_get(:@event_queue)
      expect(queue.length).to eq(1)
      expect(queue[0][:type]).to eq('trace-create')
      expect(queue[0][:body]['name']).to eq('converted')
    end

    it 'reconstructs full body from trace_ref when trace-update is converted to trace-create' do
      trace = client.trace(id: 'trace-flushed', name: 'my-trace', input: 'hi')
      client.instance_variable_get(:@event_queue).clear

      trace.update(output: 'bye')

      queue = client.instance_variable_get(:@event_queue)
      expect(queue.length).to eq(1)
      expect(queue[0][:type]).to eq('trace-create')
      expect(queue[0][:body]['name']).to eq('my-trace')
      expect(queue[0][:body]['input']).to eq('hi')
      expect(queue[0][:body]['output']).to eq('bye')
    end

    it 're-prepares the reconstructed trace_ref body (camelCase, environment, mask)' do
      masked = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        retries: 0,
        environment: 'production',
        mask: ->(value) { value.to_s.upcase }
      )

      trace = masked.trace(
        id: 'trace-flushed',
        name: 'my-trace',
        user_id: 'user-1',
        session_id: 'sess-1',
        input: 'secret-in'
      )
      masked.instance_variable_get(:@event_queue).clear

      trace.update(output: 'secret-out')

      body = masked.instance_variable_get(:@event_queue).last[:body]
      expect(body.keys).to all(be_a(String))
      expect(body).to include(
        'userId' => 'user-1',
        'sessionId' => 'sess-1',
        'environment' => 'production',
        'input' => 'SECRET-IN',
        'output' => 'SECRET-OUT'
      )
      expect(body).not_to have_key(:user_id)
      expect(body).not_to have_key('user_id')
    end

    it 'prepends re-queued events to the queue to preserve chronological order' do
      client.instance_variable_set(:@event_queue, Concurrent::Array.new)
      events = [
        { id: '1', type: 'trace-create', body: { 'id' => '1' } },
        { id: '2', type: 'span-create', body: { 'id' => '2' } }
      ]
      client.send(:requeue_events, events, Langfuse::NetworkError.new('timeout'))

      client.trace(id: '3', name: 'new')

      queued_ids = client.instance_variable_get(:@event_queue).map { |e| e[:body]['id'] }
      expect(queued_ids).to eq(%w[1 2 3])
    end

    it 'returns self and merges metadata on Trace#update' do
      trace = client.trace(id: 'trace-meta', metadata: { a: 1 })
      result = trace.update(metadata: { b: 2 })

      expect(result).to be(trace)
      expect(trace.metadata).to eq({ a: 1, b: 2 })
    end

    it 'prints warning for trace-update missing trace_id in debug mode' do
      expect do
        debug_client.enqueue_event('trace-update', { name: 'no-id' })
      end.to output(/Warning: trace-update event missing trace_id/).to_stdout

      queue = debug_client.instance_variable_get(:@event_queue)
      expect(queue).to be_empty
    end
  end

  describe '#handle_response' do
    let(:mock_response) { double('response', status: 200, body: {}) }

    it 'returns response for 2xx status' do
      result = client.send(:handle_response, mock_response)
      expect(result).to eq(mock_response)
    end

    it 'raises AuthenticationError for 401' do
      response = double('response', status: 401, body: 'Unauthorized')
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::AuthenticationError, /Authentication failed/)
    end

    it 'raises ValidationError for 404 with HTML body' do
      response = double('response', status: 404, body: '<!DOCTYPE html><html>Not Found</html>')
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::ValidationError, /Server returned HTML page/)
    end

    it 'raises ValidationError for 404 with JSON body' do
      response = double('response', status: 404, body: { 'error' => 'not found' })
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::ValidationError, /Resource not found/)
    end

    it 'raises RateLimitError for 429' do
      response = double('response', status: 429, body: 'Too Many Requests')
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::RateLimitError, /Rate limit exceeded/)
    end

    it 'raises ValidationError for 400 with hash error details' do
      response = double('response', status: 400, body: { 'error' => 'bad request' })
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::ValidationError, /Error details: bad request/)
    end

    it 'raises ValidationError for 400 with string body' do
      response = double('response', status: 400, body: 'something went wrong')
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::ValidationError, /Error details: something went wrong/)
    end

    it 'raises ValidationError with discriminator message for union/discriminator errors' do
      response = double('response', status: 400, body: 'invalid_union discriminator error')
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::ValidationError, /Event type validation failed/)
    end

    it 'raises APIError for 500' do
      response = double('response', status: 500, body: 'Internal Server Error')
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::APIError, /Server error/)
    end

    it 'raises APIError for unexpected status codes' do
      response = double('response', status: 600, body: 'Unknown')
      expect do
        client.send(:handle_response, response)
      end.to raise_error(Langfuse::APIError, /Unexpected response/)
    end
  end

  describe '#send_batch with debug mode' do
    it 'filters out events with empty type' do
      events = [
        { id: 'e1', type: '', body: { name: 'test' }, timestamp: Time.now.iso8601 },
        { id: 'e2', type: 'trace-create', body: { name: 'valid' }, timestamp: Time.now.iso8601 }
      ]

      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect do
        debug_client.send(:send_batch, events)
      end.to output(/Event with empty type detected/).to_stdout
    end

    it 'filters out events with nil body' do
      events = [
        { id: 'e1', type: 'trace-create', body: nil, timestamp: Time.now.iso8601 },
        { id: 'e2', type: 'trace-create', body: { name: 'valid' }, timestamp: Time.now.iso8601 }
      ]

      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect do
        debug_client.send(:send_batch, events)
      end.to output(/Event with empty body detected/).to_stdout
    end

    it 'does nothing when all events are filtered out' do
      events = [
        { id: 'e1', type: '', body: nil, timestamp: Time.now.iso8601 }
      ]

      expect do
        debug_client.send(:send_batch, events)
      end.to output(/No valid events to send/).to_stdout

      expect(WebMock).not_to have_requested(:post, 'https://test.langfuse.com/api/public/ingestion')
    end
  end

  describe '#flush behavior' do
    it 'dequeues events and sends batch' do
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      client.enqueue_event('trace-create', { id: 'trace-1', name: 'test' })
      client.flush

      queue = client.instance_variable_get(:@event_queue)
      expect(queue).to be_empty
      expect(WebMock).to have_requested(:post, 'https://test.langfuse.com/api/public/ingestion')
    end
  end

  describe 'HTTP methods' do
    it '#put sends a PUT request' do
      stub_request(:put, 'https://test.langfuse.com/api/test')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      client.send(:put, '/api/test', { key: 'value' })

      expect(WebMock).to have_requested(:put, 'https://test.langfuse.com/api/test')
    end

    it '#delete sends a DELETE request' do
      stub_request(:delete, 'https://test.langfuse.com/api/test')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      client.send(:delete, '/api/test')

      expect(WebMock).to have_requested(:delete, 'https://test.langfuse.com/api/test')
    end

    it '#patch sends a PATCH request' do
      stub_request(:patch, 'https://test.langfuse.com/api/test')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      client.send(:patch, '/api/test', { key: 'value' })

      expect(WebMock).to have_requested(:patch, 'https://test.langfuse.com/api/test')
    end
  end

  describe 'error handling in request' do
    it 'raises Langfuse::TimeoutError on Faraday::TimeoutError' do
      stub_request(:get, 'https://test.langfuse.com/api/test')
        .to_raise(Faraday::TimeoutError.new('request timed out'))

      expect do
        client.send(:get, '/api/test')
      end.to raise_error(Langfuse::TimeoutError, /Request timed out/)
    end

    it 'raises Langfuse::NetworkError on Faraday::ConnectionFailed after retries exhausted' do
      low_retry_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        retries: 1
      )

      stub_request(:get, 'https://test.langfuse.com/api/test')
        .to_raise(Faraday::ConnectionFailed.new('connection refused'))

      expect do
        low_retry_client.send(:get, '/api/test')
      end.to raise_error(Langfuse::NetworkError, /Connection failed/)
    end

    it 'keeps AuthenticationError for 401 responses' do
      stub_request(:get, 'https://test.langfuse.com/api/test')
        .to_return(status: 401, body: { error: 'unauthorized' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect do
        client.send(:get, '/api/test')
      end.to raise_error(Langfuse::AuthenticationError, /Authentication failed/)
    end

    it 'keeps RateLimitError for 429 responses' do
      stub_request(:get, 'https://test.langfuse.com/api/test')
        .to_return(status: 429, body: 'slow down', headers: { 'Content-Type' => 'text/plain' })

      expect do
        client.send(:get, '/api/test')
      end.to raise_error(Langfuse::RateLimitError, /Rate limit exceeded/)
    end

    it 'keeps ValidationError for 4xx responses' do
      stub_request(:get, 'https://test.langfuse.com/api/test')
        .to_return(status: 422, body: { error: 'bad field' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect do
        client.send(:get, '/api/test')
      end.to raise_error(Langfuse::ValidationError, /Client error \(422\)/)
    end
  end

  describe 'ingestion_mode configuration' do
    it 'accepts a string mode from the environment' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('LANGFUSE_INGESTION_MODE', nil).and_return('OTEL')

      expect(Langfuse::Client.new(public_key: 'k', secret_key: 's', auto_flush: false).ingestion_mode).to eq(:otel)
    end

    it 'warns and falls back to legacy for an unknown mode' do
      log_output = StringIO.new

      mode_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's', auto_flush: false,
        ingestion_mode: 'otlp', logger: Logger.new(log_output)
      )

      expect(mode_client.ingestion_mode).to eq(:legacy)
      expect(log_output.string).to include('Unknown Langfuse ingestion_mode :otlp')
    end
  end

  describe 'http_adapter configuration' do
    it 'falls back to the default adapter when the configured one is not installed' do
      log_output = StringIO.new

      adapter_client = Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        http_adapter: :not_installed_adapter,
        logger: Logger.new(log_output)
      )

      stub_request(:get, 'https://test.langfuse.com/api/test')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect(adapter_client.send(:get, '/api/test').status).to eq(200)
      expect(log_output.string).to include('could not use the :not_installed_adapter Faraday adapter')
    end
  end

  describe 'transient failure retries' do
    let(:retrying_client) do
      Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        retries: 2
      )
    end
    let(:url) { 'https://test.langfuse.com/api/test' }

    before { allow(retrying_client).to receive(:sleep) }

    it 'retries a 429 and waits for the number of seconds in Retry-After' do
      stub_request(:get, url).to_return(
        { status: 429, body: 'slow down', headers: { 'Retry-After' => '2' } },
        { status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' } }
      )

      response = retrying_client.send(:get, '/api/test')

      expect(response.status).to eq(200)
      expect(retrying_client).to have_received(:sleep).with(2.0).once
      expect(WebMock).to have_requested(:get, url).twice
    end

    it 'accepts an HTTP date in Retry-After' do
      stub_request(:get, url).to_return(
        { status: 503, body: 'unavailable', headers: { 'Retry-After' => (Time.now + 3).httpdate } },
        { status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' } }
      )

      retrying_client.send(:get, '/api/test')

      expect(retrying_client).to have_received(:sleep).with(a_value_between(1.0, 3.0))
    end

    it 'clamps an excessive Retry-After to the maximum delay' do
      stub_request(:get, url).to_return(
        { status: 429, body: 'slow down', headers: { 'Retry-After' => '600' } },
        { status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' } }
      )

      retrying_client.send(:get, '/api/test')

      expect(retrying_client).to have_received(:sleep).with(Langfuse::Client::MAX_RETRY_DELAY_SECONDS.to_f)
    end

    it 'gives up on a 5xx after the configured number of retries, backing off with jitter' do
      stub_request(:get, url).to_return(status: 500, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { retrying_client.send(:get, '/api/test') }.to raise_error(Langfuse::APIError)

      expect(WebMock).to have_requested(:get, url).times(3)
      expect(retrying_client).to have_received(:sleep)
        .with(a_value_between(0, Langfuse::Client::MAX_RETRY_DELAY_SECONDS)).twice
    end

    it 'does not retry a validation error' do
      stub_request(:get, url).to_return(status: 422, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { retrying_client.send(:get, '/api/test') }.to raise_error(Langfuse::ValidationError)

      expect(WebMock).to have_requested(:get, url).once
      expect(retrying_client).not_to have_received(:sleep)
    end

    it 'does not retry an authentication error' do
      stub_request(:get, url).to_return(status: 401, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { retrying_client.send(:get, '/api/test') }.to raise_error(Langfuse::AuthenticationError)

      expect(WebMock).to have_requested(:get, url).once
    end
  end

  describe 'configuration precedence' do
    around do |example|
      config = Langfuse.configuration
      previous = { public_key: config.public_key, secret_key: config.secret_key,
                   timeout: config.timeout, retries: config.retries }

      example.run

      previous.each { |attribute, value| config.public_send("#{attribute}=", value) }
      Langfuse.reset!
    end

    it 'honors timeout and retries set through Langfuse.configure' do
      Langfuse.configure do |config|
        config.public_key = 'test_key'
        config.secret_key = 'test_secret'
        config.timeout = 77
        config.retries = 9
      end

      configured_client = Langfuse::Client.new(auto_flush: false, shutdown_on_exit: false)

      expect(configured_client.timeout).to eq(77)
      expect(configured_client.retries).to eq(9)
    end

    it 'lets explicit arguments win over configured values' do
      Langfuse.configure do |config|
        config.public_key = 'test_key'
        config.secret_key = 'test_secret'
        config.timeout = 77
      end

      configured_client = Langfuse::Client.new(timeout: 5, auto_flush: false, shutdown_on_exit: false)

      expect(configured_client.timeout).to eq(5)
    end
  end
end
