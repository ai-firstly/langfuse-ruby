# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::OtelExporter do
  let(:connection) { instance_double(Faraday::Connection) }
  let(:exporter) { described_class.new(connection: connection, debug: false) }

  describe '#export' do
    it 'sends OTLP JSON payload to the OTEL endpoint' do
      events = [
        {
          id: 'evt-1',
          type: 'trace-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: { 'id' => 'trace-abc', 'name' => 'test-trace' }
        }
      ]

      response = instance_double(Faraday::Response)
      expect(connection).to receive(:post).with('/api/public/otel/v1/traces').and_yield(
        double('request', headers: {}, body: nil).tap do |req|
          allow(req).to receive(:headers=)
          allow(req).to receive(:[]=)
          headers_hash = {}
          allow(req).to receive(:headers).and_return(headers_hash)
          allow(req).to receive(:body=)
        end
      ).and_return(response)

      result = exporter.export(events)
      expect(result).to eq(response)
    end
  end

  describe 'trace span conversion' do
    it 'converts trace-create event to root OTEL span' do
      events = [
        {
          id: 'evt-1',
          type: 'trace-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: {
            'id' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name' => 'my-trace',
            'userId' => 'user-123',
            'sessionId' => 'sess-456',
            'tags' => %w[prod demo],
            'input' => { 'query' => 'hello' },
            'output' => { 'answer' => 'world' },
            'release' => 'v1.0',
            'version' => '2',
            'timestamp' => '2025-01-01T00:00:00.000Z'
          }
        }
      ]

      payload = capture_payload(events)

      resource_spans = payload[:resourceSpans]
      expect(resource_spans.length).to eq(1)

      spans = resource_spans[0][:scopeSpans][0][:spans]
      expect(spans.length).to eq(1)

      span = spans[0]
      expect(span[:name]).to eq('my-trace')
      expect(span[:traceId]).to eq('a1b2c3d4e5f67890abcdef1234567890')
      expect(span[:spanId]).to eq('a1b2c3d4e5f67890')
      expect(span[:kind]).to eq(1)

      attrs = attrs_to_hash(span[:attributes])
      expect(attrs['langfuse.trace.name']).to eq('my-trace')
      expect(attrs['langfuse.user.id']).to eq('user-123')
      expect(attrs['langfuse.session.id']).to eq('sess-456')
      expect(attrs['langfuse.release']).to eq('v1.0')
      expect(attrs['langfuse.version']).to eq('2')
    end
  end

  describe 'span conversion' do
    it 'converts span-create event to child OTEL span' do
      events = [
        {
          id: 'evt-1',
          type: 'span-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: {
            'id' => 'span-1111-2222-3333-444444444444',
            'traceId' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name' => 'retrieval',
            'startTime' => '2025-01-01T00:00:01.000Z',
            'endTime' => '2025-01-01T00:00:02.000Z',
            'input' => { 'query' => 'search term' },
            'level' => 'INFO'
          }
        }
      ]

      payload = capture_payload(events)
      span = payload[:resourceSpans][0][:scopeSpans][0][:spans][0]

      expect(span[:name]).to eq('retrieval')
      # Parent should be the trace root span
      expect(span[:parentSpanId]).to eq('a1b2c3d4e5f67890')

      attrs = attrs_to_hash(span[:attributes])
      expect(attrs['langfuse.observation.type']).to eq('span')
      expect(attrs['langfuse.observation.level']).to eq('INFO')
    end

    it 'sets parentSpanId to parent observation when provided' do
      events = [
        {
          id: 'evt-1',
          type: 'span-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: {
            'id' => 'span-child-1234-5678-901234567890',
            'traceId' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name' => 'child-span',
            'startTime' => '2025-01-01T00:00:01.000Z',
            'parentObservationId' => 'span-parent-aabb-ccdd-eeff11223344'
          }
        }
      ]

      payload = capture_payload(events)
      span = payload[:resourceSpans][0][:scopeSpans][0][:spans][0]

      expect(span[:parentSpanId]).to eq('spanparentaabbcc')
    end
  end

  describe 'generation conversion' do
    it 'converts generation-create event with gen_ai attributes' do
      events = [
        {
          id: 'evt-1',
          type: 'generation-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: {
            'id' => 'gen-1111-2222-3333-444444444444',
            'traceId' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name' => 'openai-call',
            'model' => 'gpt-4',
            'modelParameters' => { 'temperature' => 0.7, 'maxTokens' => 100 },
            'input' => [{ 'role' => 'user', 'content' => 'Hello' }],
            'output' => { 'content' => 'Hi there!' },
            'usage' => { 'promptTokens' => 10, 'completionTokens' => 5, 'totalTokens' => 15 },
            'startTime' => '2025-01-01T00:00:01.000Z',
            'endTime' => '2025-01-01T00:00:02.000Z',
            'completionStartTime' => '2025-01-01T00:00:01.500Z'
          }
        }
      ]

      payload = capture_payload(events)
      span = payload[:resourceSpans][0][:scopeSpans][0][:spans][0]

      expect(span[:name]).to eq('openai-call')

      attrs = attrs_to_hash(span[:attributes])
      expect(attrs['langfuse.observation.type']).to eq('generation')
      expect(attrs['gen_ai.request.model']).to eq('gpt-4')
      expect(attrs['gen_ai.request.temperature']).to eq(0.7)
      expect(attrs['gen_ai.request.maxTokens']).to eq(100)
      expect(attrs['gen_ai.usage.prompt_tokens']).to eq(10)
      expect(attrs['gen_ai.usage.completion_tokens']).to eq(5)
      expect(attrs['gen_ai.usage.total_tokens']).to eq(15)
      expect(attrs['langfuse.observation.completion_start_time']).to eq('2025-01-01T00:00:01.500Z')
    end
  end

  describe 'event conversion' do
    it 'converts event-create to zero-duration OTEL span' do
      events = [
        {
          id: 'evt-1',
          type: 'event-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: {
            'id' => 'event-1111-2222-3333-444444444444',
            'traceId' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name' => 'user-click',
            'startTime' => '2025-01-01T00:00:01.000Z',
            'input' => { 'action' => 'click' }
          }
        }
      ]

      payload = capture_payload(events)
      span = payload[:resourceSpans][0][:scopeSpans][0][:spans][0]

      expect(span[:name]).to eq('user-click')
      expect(span[:startTimeUnixNano]).to eq(span[:endTimeUnixNano])

      attrs = attrs_to_hash(span[:attributes])
      expect(attrs['langfuse.observation.type']).to eq('event')
    end
  end

  describe 'score conversion' do
    it 'converts score-create to OTEL span' do
      events = [
        {
          id: 'evt-1',
          type: 'score-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: {
            'id' => 'score-1111-2222-3333-444444444444',
            'traceId' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name' => 'accuracy',
            'value' => 0.95,
            'comment' => 'Great result',
            'timestamp' => '2025-01-01T00:00:01.000Z'
          }
        }
      ]

      payload = capture_payload(events)
      span = payload[:resourceSpans][0][:scopeSpans][0][:spans][0]

      expect(span[:name]).to eq('score-accuracy')

      attrs = attrs_to_hash(span[:attributes])
      expect(attrs['langfuse.score.name']).to eq('accuracy')
      expect(attrs['langfuse.score.value']).to eq(0.95)
      expect(attrs['langfuse.score.comment']).to eq('Great result')
      expect(attrs['langfuse.observation.type']).to eq('score')
    end

    it 'skips score without traceId' do
      events = [
        {
          id: 'evt-1',
          type: 'score-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: { 'name' => 'test', 'value' => 1.0 }
        }
      ]

      payload = capture_payload(events)
      expect(payload[:resourceSpans]).to eq([])
    end
  end

  describe 'ID conversion' do
    it 'converts UUID to 32-char trace ID' do
      trace_id = exporter.send(:to_otel_trace_id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890')
      expect(trace_id).to eq('a1b2c3d4e5f67890abcdef1234567890')
      expect(trace_id.length).to eq(32)
    end

    it 'converts UUID to 16-char span ID' do
      span_id = exporter.send(:to_otel_span_id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890')
      expect(span_id).to eq('a1b2c3d4e5f67890')
      expect(span_id.length).to eq(16)
    end

    it 'handles nil IDs' do
      expect(exporter.send(:to_otel_trace_id, nil)).to eq('0' * 32)
      expect(exporter.send(:to_otel_span_id, nil)).to eq('0' * 16)
    end
  end

  describe 'timestamp conversion' do
    it 'converts ISO8601 to nanoseconds' do
      nanos = exporter.send(:to_unix_nano, '2025-01-01T00:00:00.000Z')
      expect(nanos).to match(/\A\d+\z/)
      expect(nanos.to_i).to be > 0
    end

    it 'handles nil timestamps' do
      expect(exporter.send(:to_unix_nano, nil)).to eq('0')
    end
  end

  describe 'resource metadata' do
    it 'includes SDK metadata in resource attributes' do
      events = [
        {
          id: 'evt-1',
          type: 'trace-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: { 'id' => 'trace-abc', 'name' => 'test', 'timestamp' => '2025-01-01T00:00:00.000Z' }
        }
      ]

      payload = capture_payload(events)
      resource = payload[:resourceSpans][0][:resource]
      attrs = attrs_to_hash(resource[:attributes])

      expect(attrs['service.name']).to eq('langfuse-ruby')
      expect(attrs['telemetry.sdk.name']).to eq('langfuse-ruby')
      expect(attrs['telemetry.sdk.version']).to eq(Langfuse::VERSION)
    end
  end

  describe 'enhanced observation types' do
    it 'preserves as_type in langfuse.observation.type' do
      events = [
        {
          id: 'evt-1',
          type: 'span-create',
          timestamp: '2025-01-01T00:00:00.000Z',
          body: {
            'id' => 'span-1111-2222-3333-444444444444',
            'traceId' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name' => 'my-agent',
            'type' => 'agent',
            'startTime' => '2025-01-01T00:00:01.000Z'
          }
        }
      ]

      payload = capture_payload(events)
      span = payload[:resourceSpans][0][:scopeSpans][0][:spans][0]

      attrs = attrs_to_hash(span[:attributes])
      expect(attrs['langfuse.observation.type']).to eq('agent')
    end
  end

  private

  # Helper to capture the payload that would be sent via the exporter
  def capture_payload(events)
    exporter.send(:build_resource_spans, events)
    # Build the full payload structure
    { resourceSpans: exporter.send(:build_resource_spans, events) }
  end

  # Convert OTEL attributes array to a simple key-value hash for easier testing
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
                         elsif value.key?(:arrayValue)
                           value[:arrayValue][:values].map { |v| v[:stringValue] }
                         end
    end
  end
end
