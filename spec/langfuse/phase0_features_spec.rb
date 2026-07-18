# frozen_string_literal: true

require_relative '../spec_helper'

# Phase 0 features: environment, sample_rate, mask, flush_at, batch chunking,
# 207 ingestion errors, score full fields, OTel score routing, idempotent
# shutdown, LANGFUSE_BASE_URL, trace public field, generation
# usage_details/cost_details/prompt linking.
RSpec.describe 'Langfuse Phase 0 features' do
  let(:client) do
    Langfuse::Client.new(
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com',
      auto_flush: false
    )
  end

  after { Langfuse.reset! }

  describe 'LANGFUSE_BASE_URL env var fallback' do
    it 'uses LANGFUSE_BASE_URL when LANGFUSE_HOST is absent' do
      ENV.delete('LANGFUSE_HOST')
      ENV['LANGFUSE_BASE_URL'] = 'https://eu.cloud.langfuse.com'

      base_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's', auto_flush: false
      )
      expect(base_client.host).to eq('https://eu.cloud.langfuse.com')

      ENV.delete('LANGFUSE_BASE_URL')
    end

    it 'prefers LANGFUSE_HOST over LANGFUSE_BASE_URL' do
      ENV['LANGFUSE_HOST'] = 'https://us.cloud.langfuse.com'
      ENV['LANGFUSE_BASE_URL'] = 'https://eu.cloud.langfuse.com'

      base_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's', auto_flush: false
      )
      expect(base_client.host).to eq('https://us.cloud.langfuse.com')

      ENV.delete('LANGFUSE_HOST')
      ENV.delete('LANGFUSE_BASE_URL')
    end
  end

  describe 'environment injection' do
    it 'injects the default environment into trace bodies' do
      env_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, environment: 'production'
      )

      env_client.trace(name: 't')
      body = env_client.instance_variable_get(:@event_queue).last[:body]
      expect(body['environment']).to eq('production')
    end

    it 'injects the default environment into score bodies' do
      env_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, environment: 'staging'
      )

      env_client.score(name: 'n', value: 1, trace_id: 't1')
      body = env_client.instance_variable_get(:@event_queue).last[:body]
      expect(body['environment']).to eq('staging')
    end

    it 'does not override an explicitly provided environment' do
      env_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, environment: 'production'
      )

      env_client.trace(name: 't', environment: 'custom-env')
      body = env_client.instance_variable_get(:@event_queue).last[:body]
      expect(body['environment']).to eq('custom-env')
    end

    it 'reads LANGFUSE_TRACING_ENVIRONMENT env var' do
      ENV['LANGFUSE_TRACING_ENVIRONMENT'] = 'ci'
      env_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false
      )
      expect(env_client.environment).to eq('ci')
      ENV.delete('LANGFUSE_TRACING_ENVIRONMENT')
    end
  end

  describe 'sample_rate' do
    it 'drops events for traces that fall outside the sample' do
      sampled = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, sample_rate: 0.0
      )

      sampled.trace(id: 'trace-fixed', name: 't')
      expect(sampled.instance_variable_get(:@event_queue)).to be_empty
    end

    it 'keeps all events when sample_rate is 1.0' do
      sampled = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, sample_rate: 1.0
      )

      sampled.trace(id: 'trace-fixed', name: 't')
      expect(sampled.instance_variable_get(:@event_queue).length).to eq(1)
    end

    it 'applies the same decision to all events of a trace' do
      sampled = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, sample_rate: 0.5
      )

      sampled.trace(id: 'trace-abc', name: 't')
      trace_kept = sampled.instance_variable_get(:@event_queue).any? do |e|
        e[:body]['id'] == 'trace-abc'
      end

      sampled.span(trace_id: 'trace-abc', name: 's')
      span_kept = sampled.instance_variable_get(:@event_queue).any? do |e|
        e[:type] == 'span-create'
      end

      expect(trace_kept).to eq(span_kept)
    end

    it 'ignores out-of-range sample rates' do
      env_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, sample_rate: 2.0
      )
      expect(env_client.sample_rate).to be_nil
    end
  end

  describe 'mask function' do
    it 'applies the mask to input, output and metadata' do
      masked = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        mask: ->(value) { value.to_s.upcase }
      )

      masked.trace(name: 't', input: 'hello', output: 'world', metadata: 'secret')
      body = masked.instance_variable_get(:@event_queue).last[:body]
      expect(body['input']).to eq('HELLO')
      expect(body['output']).to eq('WORLD')
      expect(body['metadata']).to eq('SECRET')
    end

    it 'does not touch fields that are absent' do
      masked = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false,
        mask: ->(_value) { 'X' }
      )

      masked.trace(name: 't')
      body = masked.instance_variable_get(:@event_queue).last[:body]
      expect(body).not_to have_key('input')
      expect(body).not_to have_key('output')
    end

    it 'ignores non-callable masks' do
      env_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, mask: 'not-a-proc'
      )
      expect(env_client.mask).to be_nil
    end
  end

  describe 'flush_at threshold' do
    it 'triggers a flush once the queue reaches flush_at' do
      at_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: true, flush_at: 2, flush_interval: 600
      )

      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      at_client.trace(name: 't1')
      sleep 0.05
      expect(WebMock).not_to have_requested(:post, 'https://test.langfuse.com/api/public/ingestion')

      at_client.trace(name: 't2')
      sleep 0.3

      expect(WebMock).to have_requested(:post, 'https://test.langfuse.com/api/public/ingestion')
      at_client.shutdown
    end
  end

  describe 'batch chunking by 3.5MB' do
    it 'splits a large batch into multiple requests' do
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      # Build events that each exceed half the limit so two must be split.
      big_payload = { 'input' => 'x' * ((Langfuse::Client::MAX_BATCH_SIZE_BYTES / 2) + 100) }
      events = Array.new(2) do |i|
        { id: "evt-#{i}", type: 'trace-create', timestamp: Time.now.iso8601, body: { 'id' => "t#{i}", 'name' => 'big' }.merge(big_payload) }
      end

      client.send(:send_batch, events)

      expect(WebMock).to have_requested(:post, 'https://test.langfuse.com/api/public/ingestion').twice
    end

    it 'drops events exceeding the max batch size' do
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      huge = { 'input' => 'x' * (Langfuse::Client::MAX_BATCH_SIZE_BYTES + 10) }
      events = [
        { id: 'huge', type: 'trace-create', timestamp: Time.now.iso8601, body: { 'id' => 'h', 'name' => 'huge' }.merge(huge) },
        { id: 'ok', type: 'trace-create', timestamp: Time.now.iso8601, body: { 'id' => 'ok', 'name' => 'ok' } }
      ]

      client.send(:send_batch, events)
      # Only the small event is sent: assert via a block matcher on the request body
      expect(WebMock).to(have_requested(:post, 'https://test.langfuse.com/api/public/ingestion')
        .with { |req| JSON.parse(req.body)['batch'].length == 1 })
    end
  end

  describe 'ingestion 207 partial errors' do
    it 'logs per-event errors from a 207 response' do
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(
          status: 207,
          body: { errors: [{ id: 'evt-1', status: 400, message: 'bad body' }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      logger = Logger.new(IO::NULL)
      allow(logger).to receive(:warn)

      log_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: false, logger: logger
      )

      log_client.enqueue_event('trace-create', id: 't', name: 't')
      log_client.flush

      expect(logger).to have_received(:warn).with(/partial failure.*evt-1.*bad body/)
    end
  end

  describe 'score full fields' do
    it 'passes session_id, dataset_run_id, metadata, config_id, id, queue_id, environment' do
      expect(client).to receive(:enqueue_event).with(
        'score-create',
        hash_including(
          id: 'score-1',
          trace_id: 'trace-1',
          observation_id: 'obs-1',
          session_id: 'sess-1',
          dataset_run_id: 'run-1',
          metadata: { source: 'test' },
          config_id: 'cfg-1',
          queue_id: 'q-1',
          environment: 'production',
          name: 'accuracy',
          value: 0.9,
          data_type: 'NUMERIC',
          comment: 'great'
        )
      )

      client.score(
        id: 'score-1',
        trace_id: 'trace-1',
        observation_id: 'obs-1',
        session_id: 'sess-1',
        dataset_run_id: 'run-1',
        metadata: { source: 'test' },
        config_id: 'cfg-1',
        queue_id: 'q-1',
        environment: 'production',
        name: 'accuracy',
        value: 0.9,
        data_type: 'NUMERIC',
        comment: 'great'
      )
    end

    it 'accepts string values for categorical/correction scores' do
      expect(client).to receive(:enqueue_event).with(
        'score-create',
        hash_including(name: 'label', value: 'good', data_type: 'CATEGORICAL')
      )

      client.score(name: 'label', value: 'good', data_type: 'CATEGORICAL', trace_id: 't1')
    end

    it 'is aliased as create_score' do
      expect(client.method(:create_score).original_name).to eq(:score)
    end
  end

  describe 'idempotent shutdown' do
    it 'can be called multiple times safely' do
      shutdown_client = Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        auto_flush: true, shutdown_on_exit: false
      )
      thread = shutdown_client.instance_variable_get(:@flush_thread)
      expect(thread).to receive(:kill).once

      shutdown_client.shutdown
      shutdown_client.shutdown
    end
  end

  describe 'trace public field' do
    it 'records the public flag on the trace-create event' do
      client.trace(id: 't-pub', name: 't', public: true)
      body = client.instance_variable_get(:@event_queue).last[:body]
      expect(body['public']).to eq(true)
    end

    it 'updates the public flag via trace.update' do
      trace = client.trace(id: 't-pub', name: 't')
      trace.update(public: true)
      body = client.instance_variable_get(:@event_queue).last[:body]
      expect(body['public']).to eq(true)
    end
  end

  describe 'Generation usage_details/cost_details/prompt linking' do
    it 'stores usage_details and cost_details' do
      gen = client.generation(
        trace_id: 't1', name: 'g', model: 'gpt-4o',
        usage_details: { input: 10, output: 5, cache_read: 3 },
        cost_details: { input: 0.001, output: 0.002, total: 0.003 }
      )
      expect(gen.usage_details).to eq({ input: 10, output: 5, cache_read: 3 })
      expect(gen.cost_details).to eq({ input: 0.001, output: 0.002, total: 0.003 })
    end

    it 'links a prompt via a Langfuse::Prompt object' do
      prompt = Langfuse::Prompt.new(
        'id' => 'p1', 'name' => 'greeting', 'version' => 3,
        'prompt' => 'hi', 'type' => 'text'
      )
      gen = client.generation(trace_id: 't1', name: 'g', model: 'm', prompt: prompt)
      expect(gen.prompt_name).to eq('greeting')
      expect(gen.prompt_version).to eq(3)
    end

    it 'links a prompt via a hash with name/version' do
      gen = client.generation(
        trace_id: 't1', name: 'g', model: 'm',
        prompt: { name: 'chat', version: 2 }
      )
      expect(gen.prompt_name).to eq('chat')
      expect(gen.prompt_version).to eq(2)
    end

    it 'emits promptName/promptVersion/usageDetails/costDetails in to_dict' do
      gen = client.generation(
        trace_id: 't1', name: 'g', model: 'm',
        usage_details: { input: 10 },
        cost_details: { total: 0.01 },
        prompt: { name: 'chat', version: 2 }
      )
      dict = gen.to_dict
      expect(dict[:usage_details]).to eq({ input: 10 })
      expect(dict[:cost_details]).to eq({ total: 0.01 })
      expect(dict[:prompt_name]).to eq('chat')
      expect(dict[:prompt_version]).to eq(2)
    end

    it 'updates usage_details/cost_details via #end' do
      gen = client.generation(trace_id: 't1', name: 'g', model: 'm')
      gen.end(
        output: 'resp',
        usage_details: { input: 20 },
        cost_details: { total: 0.02 }
      )
      expect(gen.usage_details).to eq({ input: 20 })
      expect(gen.cost_details).to eq({ total: 0.02 })
    end
  end

  describe 'OTel mode score routing' do
    let(:otel_client) do
      Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        ingestion_mode: :otel, auto_flush: false,
        shutdown_on_exit: false
      )
    end

    it 'sends scores through the ingestion API, not the OTLP endpoint' do
      stub_request(:post, 'https://test.langfuse.com/api/public/otel/v1/traces')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      otel_client.score(name: 'acc', value: 0.9, trace_id: 'trace-1', observation_id: 'obs-1')
      otel_client.flush

      expect(WebMock).not_to have_requested(:post, 'https://test.langfuse.com/api/public/otel/v1/traces')
      expect(WebMock).to have_requested(:post, 'https://test.langfuse.com/api/public/ingestion')
    end

    it 'normalizes score traceId/observationId to OTel hex IDs' do
      stub_request(:post, 'https://test.langfuse.com/api/public/ingestion')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      otel_client.score(
        name: 'acc', value: 0.9,
        trace_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        observation_id: '11111111-2222-3333-444444444444'
      )
      otel_client.flush

      score_body = nil
      expect(WebMock).to(have_requested(:post, 'https://test.langfuse.com/api/public/ingestion')
        .with do |req|
          score_body = JSON.parse(req.body)['batch'].first
          true
        end)
      expect(score_body['body']['traceId']).to eq('a1b2c3d4e5f67890abcdef1234567890')
      expect(score_body['body']['observationId']).to eq('1111111122223333')
    end

    it 'uses W3C hex IDs for traces and observations' do
      trace = otel_client.trace(name: 't')
      expect(trace.id).to match(/\A[0-9a-f]{32}\z/)

      span = otel_client.span(trace_id: trace.id, name: 's')
      expect(span.id).to match(/\A[0-9a-f]{16}\z/)
    end

    it 're-queues score events when OTEL export fails' do
      stub_request(:post, 'https://test.langfuse.com/api/public/otel/v1/traces')
        .to_return(status: 500, body: 'error', headers: { 'Content-Type' => 'text/plain' })

      otel_client.trace(name: 't')
      otel_client.score(name: 'acc', value: 0.9, trace_id: 'trace-1')

      expect { otel_client.flush }.to raise_error(Langfuse::APIError)

      queue = otel_client.instance_variable_get(:@event_queue)
      types = queue.map { |e| e[:type] }
      expect(types).to include('trace-create')
      expect(types).to include('score-create')
    end
  end

  describe 'OTel exporter new attributes' do
    let(:exporter) { Langfuse::OtelExporter.new(connection: instance_double(Faraday::Connection), debug: false) }

    it 'emits langfuse.environment on traces' do
      events = [{
        id: 'e1', type: 'trace-create', timestamp: '2025-01-01T00:00:00.000Z',
        body: { 'id' => 'a1b2c3d4e5f67890abcdef1234567890', 'name' => 't', 'environment' => 'prod' }
      }]
      payload = { resourceSpans: exporter.send(:build_resource_spans, events) }
      attrs = attrs_to_hash(payload[:resourceSpans][0][:scopeSpans][0][:spans][0][:attributes])
      expect(attrs['langfuse.environment']).to eq('prod')
      expect(attrs['langfuse.internal.as_root']).to eq(true)
    end

    it 'emits langfuse.trace.public when set' do
      events = [{
        id: 'e1', type: 'trace-create', timestamp: '2025-01-01T00:00:00.000Z',
        body: { 'id' => 'a1b2c3d4e5f67890abcdef1234567890', 'name' => 't', 'public' => true }
      }]
      payload = { resourceSpans: exporter.send(:build_resource_spans, events) }
      attrs = attrs_to_hash(payload[:resourceSpans][0][:scopeSpans][0][:spans][0][:attributes])
      expect(attrs['langfuse.trace.public']).to eq(true)
    end

    it 'emits usage_details, cost_details and prompt attrs on generations' do
      events = [{
        id: 'e1', type: 'generation-create', timestamp: '2025-01-01T00:00:00.000Z',
        body: {
          'id' => 'aaaa1111222233334444444444444444',
          'traceId' => 'a1b2c3d4e5f67890abcdef1234567890',
          'name' => 'g', 'model' => 'gpt-4o',
          'startTime' => '2025-01-01T00:00:01.000Z',
          'usageDetails' => { 'input' => 10 },
          'costDetails' => { 'total' => 0.01 },
          'promptName' => 'chat', 'promptVersion' => 2
        }
      }]
      payload = { resourceSpans: exporter.send(:build_resource_spans, events) }
      attrs = attrs_to_hash(payload[:resourceSpans][0][:scopeSpans][0][:spans][0][:attributes])
      expect(attrs['langfuse.observation.usage_details']).to include('input')
      expect(attrs['langfuse.observation.cost_details']).to include('total')
      expect(attrs['langfuse.observation.prompt.name']).to eq('chat')
      expect(attrs['langfuse.observation.prompt.version']).to eq(2)
    end

    def attrs_to_hash(attributes)
      attributes.each_with_object({}) do |attr, hash|
        value = attr[:value]
        hash[attr[:key]] = if value.key?(:stringValue)
                             value[:stringValue]
                           elsif value.key?(:intValue)
                             value[:intValue].to_i
                           elsif value.key?(:doubleValue)
                             value[:doubleValue]
                           elsif value.key?(:boolValue)
                             value[:boolValue]
                           end
      end
    end
  end

  describe 'prepare_event_body preserves user data' do
    it 'passes metadata values through verbatim' do
      client.trace(name: 't', metadata: { 'snake_case_key' => 1, nested: { 'another_key' => 2 } })
      body = client.instance_variable_get(:@event_queue).last[:body]
      expect(body['metadata']).to eq({ 'snake_case_key' => 1, nested: { 'another_key' => 2 } })
    end

    it 'camelizes top-level keys but leaves input untouched' do
      client.trace(name: 't', input: { 'my_field' => 'value' }, parent_observation_id: 'p1')
      body = client.instance_variable_get(:@event_queue).last[:body]
      expect(body['input']).to eq({ 'my_field' => 'value' })
    end
  end
end
