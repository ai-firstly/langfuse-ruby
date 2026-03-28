# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Client do
  let(:client) do
    Langfuse::Client.new(
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com',
      auto_flush: false
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
      client.get_prompt('cached-prompt', cache_ttl_seconds: 60)

      # Manipulate cached_at to simulate expiry
      cache = client.instance_variable_get(:@prompt_cache)
      cache_key = cache.keys.first
      cache[cache_key][:cached_at] = Time.now - 120

      client.get_prompt('cached-prompt', cache_ttl_seconds: 60)

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

    it 'converts trace-update to trace-create when no matching trace-create exists' do
      client.enqueue_event('trace-update', { id: 'trace-new', name: 'converted' })

      queue = client.instance_variable_get(:@event_queue)
      expect(queue.length).to eq(1)
      expect(queue[0][:type]).to eq('trace-create')
      expect(queue[0][:body]['name']).to eq('converted')
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
  end
end
