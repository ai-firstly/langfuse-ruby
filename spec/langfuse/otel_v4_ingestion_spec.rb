# frozen_string_literal: true

require_relative '../spec_helper'

# Client-level behavior of the OTel (Langfuse v4) ingestion path: create/update
# collapsing, payload chunking and OTLP partial-success reporting.
RSpec.describe 'OTel v4 ingestion path' do
  let(:otel_endpoint) { 'https://test.langfuse.com/api/public/otel/v1/traces' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:logger) { instance_double(Logger, debug: nil, warn: nil, error: nil) }

  let(:otel_client) do
    Langfuse::Client.new(
      public_key: 'k', secret_key: 's',
      host: 'https://test.langfuse.com',
      ingestion_mode: :otel, auto_flush: false,
      shutdown_on_exit: false, logger: logger,
      retries: 0
    )
  end

  def captured_spans(bodies)
    bodies.flat_map do |body|
      JSON.parse(body)['resourceSpans'].flat_map do |resource_span|
        resource_span['scopeSpans'].flat_map { |scope_span| scope_span['spans'] }
      end
    end
  end

  def attrs_to_hash(attributes)
    attributes.each_with_object({}) do |attr, hash|
      hash[attr['key']] = attr['value'].values.first
    end
  end

  describe 'generation create + end' do
    it 'sends a single span with the final output and token usage' do
      bodies = []
      stub_request(:post, otel_endpoint)
        .to_return do |request|
          bodies << request.body
          { status: 200, body: '{}', headers: json_headers }
        end

      generation = otel_client.generation(
        trace_id: 'a' * 32, name: 'openai-call', model: 'gpt-4o', input: 'question'
      )
      generation.end(output: 'answer', usage: { input: 3, output: 4, total: 7, unit: 'TOKENS' })
      otel_client.flush

      spans = captured_spans(bodies)
      expect(spans.length).to eq(1)

      attrs = attrs_to_hash(spans[0]['attributes'])
      expect(attrs['langfuse.observation.output']).to eq('answer')
      expect(attrs['gen_ai.usage.total_tokens']).to eq('7')
      expect(JSON.parse(attrs['langfuse.observation.usage_details']))
        .to eq({ 'input' => 3, 'output' => 4, 'total' => 7 })
    end
  end

  describe 'payload chunking' do
    it 'splits events across several OTLP requests to respect the size limit' do
      stub_const('Langfuse::Client::MAX_BATCH_SIZE_BYTES', 300)

      bodies = []
      stub_request(:post, otel_endpoint)
        .to_return do |request|
          bodies << request.body
          { status: 200, body: '{}', headers: json_headers }
        end

      otel_client.trace(name: 'first')
      otel_client.trace(name: 'second')
      otel_client.flush

      expect(bodies.length).to eq(2)
      expect(captured_spans(bodies).length).to eq(2)
    end

    it 're-queues the not-yet-sent chunks when a chunk fails' do
      stub_const('Langfuse::Client::MAX_BATCH_SIZE_BYTES', 300)
      stub_request(:post, otel_endpoint).to_return(status: 500, body: { error: 'boom' }.to_json, headers: json_headers)

      otel_client.trace(name: 'first')
      otel_client.trace(name: 'second')

      expect { otel_client.flush }.to raise_error(Langfuse::APIError)

      queue = otel_client.instance_variable_get(:@event_queue)
      expect(queue.length).to eq(2)
    end
  end

  describe 'OTLP partial success' do
    it 'warns when the endpoint reports rejected spans' do
      stub_request(:post, otel_endpoint).to_return(
        status: 200,
        body: { partialSuccess: { rejectedSpans: 2, errorMessage: 'invalid attribute' } }.to_json,
        headers: json_headers
      )

      expect(logger).to receive(:warn).with(/2 spans rejected - invalid attribute/)

      otel_client.trace(name: 'trace-with-rejects')
      otel_client.flush
    end

    it 'stays quiet when nothing was rejected' do
      stub_request(:post, otel_endpoint).to_return(
        status: 200,
        body: { partialSuccess: { rejectedSpans: 0 } }.to_json,
        headers: json_headers
      )

      expect(logger).not_to receive(:warn)

      otel_client.trace(name: 'clean-trace')
      otel_client.flush
    end
  end

  describe 'transient failure retries' do
    let(:retrying_otel_client) do
      Langfuse::Client.new(
        public_key: 'k', secret_key: 's',
        host: 'https://test.langfuse.com',
        ingestion_mode: :otel, auto_flush: false,
        shutdown_on_exit: false, logger: logger,
        retries: 2
      )
    end

    before { allow(retrying_otel_client).to receive(:sleep) }

    it 'retries transient 5xx responses and succeeds on subsequent attempt' do
      stub_request(:post, otel_endpoint).to_return(
        { status: 500, body: { error: 'temporary error' }.to_json, headers: json_headers },
        { status: 200, body: '{}', headers: json_headers }
      )

      retrying_otel_client.trace(name: 'flaky-trace')
      expect { retrying_otel_client.flush }.not_to raise_error
      expect(WebMock).to have_requested(:post, otel_endpoint).twice
    end
  end
end
