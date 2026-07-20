# frozen_string_literal: true

require 'json'
require 'securerandom'

module Langfuse
  # Converts batched Langfuse events into OTLP/HTTP JSON (ExportTraceServiceRequest)
  # and sends them to the Langfuse OTEL endpoint for v4-compatible ingestion.
  class OtelExporter
    OTEL_ENDPOINT = '/api/public/otel/v1/traces'

    class << self
      # Convert an ID (UUID or hex string) to an OTEL 32-char hex trace ID.
      # OTEL trace IDs are 16 bytes (32 hex chars). Native hex IDs pass through unchanged.
      def to_otel_trace_id(id_str)
        return '0' * 32 unless id_str

        hex = id_str.to_s.delete('-')
        hex.ljust(32, '0')[0, 32]
      end

      # Convert an ID (UUID or hex string) to an OTEL 16-char hex span ID.
      # OTEL span IDs are 8 bytes (16 hex chars). Native hex IDs pass through unchanged.
      def to_otel_span_id(id_str)
        return '0' * 16 unless id_str

        hex = id_str.to_s.delete('-')
        hex[0, 16]
      end
    end

    # @param connection [Faraday::Connection] HTTP connection to Langfuse host
    # @param debug [Boolean] whether to print debug output
    # @param logger [Logger, nil] logger for debug output
    def initialize(connection:, debug: false, logger: nil)
      @connection = connection
      @debug = debug
      @logger = logger
    end

    # Export a batch of Langfuse events as OTLP spans.
    # Note: score-create events are not part of the OTLP mapping and are
    # handled separately by the client via the ingestion API.
    # @param events [Array<Hash>] array of event hashes from the event queue
    # @return [Faraday::Response]
    def export(events)
      resource_spans = build_resource_spans(events)
      payload = { resourceSpans: resource_spans }

      log_debug { "OTEL export payload: #{JSON.pretty_generate(payload)}" }

      @connection.post(OTEL_ENDPOINT) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = JSON.generate(payload)
      end
    end

    private

    def log_debug(&block)
      return unless @debug

      if @logger
        @logger.debug(block.call)
      else
        puts block.call
      end
    end

    # Build the top-level resourceSpans array from events.
    # Groups events by trace_id, producing one scopeSpan per trace.
    def build_resource_spans(events)
      grouped = group_events_by_trace(events)

      scope_spans = grouped.map do |_trace_id, trace_events|
        spans = trace_events.filter_map { |event| convert_event_to_span(event) }
        next if spans.empty?

        { scope: { name: 'langfuse-ruby', version: Langfuse::VERSION }, spans: spans }
      end.compact

      return [] if scope_spans.empty?

      [{
        resource: {
          attributes: [
            { key: 'service.name', value: { stringValue: 'langfuse-ruby' } },
            { key: 'telemetry.sdk.name', value: { stringValue: 'langfuse-ruby' } },
            { key: 'telemetry.sdk.version', value: { stringValue: Langfuse::VERSION } }
          ]
        },
        scopeSpans: scope_spans
      }]
    end

    # Group events by their trace ID for proper OTEL span hierarchy.
    def group_events_by_trace(events)
      groups = Hash.new { |h, k| h[k] = [] }

      events.each do |event|
        body = event[:body] || {}
        trace_id = body['traceId'] || body['trace_id'] || body['id'] || 'unknown'
        groups[trace_id] << event
      end

      groups
    end

    # Convert a single Langfuse event to an OTLP span hash, or nil if not convertible.
    def convert_event_to_span(event)
      type = event[:type]
      body = event[:body] || {}

      case type
      when 'trace-create'
        build_trace_span(body)
      when 'span-create', 'span-update'
        build_observation_span(body, 'span')
      when 'generation-create', 'generation-update'
        build_observation_span(body, 'generation')
      when 'event-create'
        build_event_span(body)
      end
    end

    # Build a root OTEL span for a Langfuse trace.
    def build_trace_span(body)
      trace_id = to_otel_trace_id(body['id'])
      span_id = to_otel_span_id(body['id'])

      attributes = []
      add_attr(attributes, 'langfuse.trace.name', body['name'])
      add_attr(attributes, 'langfuse.user.id', body['userId'])
      add_attr(attributes, 'langfuse.session.id', body['sessionId'])
      add_attr(attributes, 'langfuse.release', body['release'])
      add_attr(attributes, 'langfuse.version', body['version'])
      add_attr(attributes, 'langfuse.environment', body['environment'])
      add_attr(attributes, 'langfuse.trace.public', body['public']) unless body['public'].nil?
      add_attr(attributes, 'langfuse.internal.as_root', true)
      add_json_attr(attributes, 'langfuse.trace.input', body['input'])
      add_json_attr(attributes, 'langfuse.trace.output', body['output'])
      add_json_attr(attributes, 'langfuse.trace.metadata', body['metadata'])

      tags = body['tags']
      if tags.is_a?(Array) && !tags.empty?
        add_array_attr(attributes, 'langfuse.trace.tags', tags)
      end

      {
        traceId: trace_id,
        spanId: span_id,
        name: body['name'] || 'trace',
        kind: 1, # SPAN_KIND_INTERNAL
        startTimeUnixNano: to_unix_nano(body['timestamp']),
        endTimeUnixNano: to_unix_nano(body['timestamp']),
        attributes: attributes,
        status: { code: 1 } # STATUS_CODE_OK
      }
    end

    # Build an OTEL span for a Langfuse span or generation observation.
    def build_observation_span(body, obs_type)
      trace_id = to_otel_trace_id(body['traceId'])
      span_id = to_otel_span_id(body['id'])

      span = {
        traceId: trace_id,
        spanId: span_id,
        name: body['name'] || obs_type,
        kind: 1, # SPAN_KIND_INTERNAL
        startTimeUnixNano: to_unix_nano(body['startTime']),
        endTimeUnixNano: to_unix_nano(body['endTime'] || body['startTime']),
        attributes: build_observation_attributes(body, obs_type),
        status: { code: 1 }
      }

      # Set parent span ID
      parent_id = body['parentObservationId']
      if parent_id
        span[:parentSpanId] = to_otel_span_id(parent_id)
      else
        # Parent is the trace root span
        span[:parentSpanId] = to_otel_span_id(body['traceId'])
      end

      span
    end

    # Build an OTEL span for a Langfuse event (zero-duration span).
    def build_event_span(body)
      trace_id = to_otel_trace_id(body['traceId'])
      span_id = to_otel_span_id(body['id'])
      timestamp = to_unix_nano(body['startTime'])

      attributes = []
      add_attr(attributes, 'langfuse.observation.type', 'event')
      add_json_attr(attributes, 'langfuse.observation.input', body['input'])
      add_json_attr(attributes, 'langfuse.observation.output', body['output'])
      add_json_attr(attributes, 'langfuse.observation.metadata', body['metadata'])
      add_attr(attributes, 'langfuse.observation.level', body['level'])
      add_attr(attributes, 'langfuse.observation.status_message', body['statusMessage'])

      span = {
        traceId: trace_id,
        spanId: span_id,
        name: body['name'] || 'event',
        kind: 1,
        startTimeUnixNano: timestamp,
        endTimeUnixNano: timestamp,
        attributes: attributes,
        status: { code: 1 }
      }

      parent_id = body['parentObservationId']
      if parent_id
        span[:parentSpanId] = to_otel_span_id(parent_id)
      elsif body['traceId']
        span[:parentSpanId] = to_otel_span_id(body['traceId'])
      end

      span
    end

    # Build OTEL attributes for a span/generation observation.
    def build_observation_attributes(body, obs_type)
      attributes = []
      effective_type = body['type'] || obs_type
      add_attr(attributes, 'langfuse.observation.type', effective_type)
      add_json_attr(attributes, 'langfuse.observation.input', body['input'])
      add_json_attr(attributes, 'langfuse.observation.output', body['output'])
      add_json_attr(attributes, 'langfuse.observation.metadata', body['metadata'])
      add_attr(attributes, 'langfuse.observation.level', body['level'])
      add_attr(attributes, 'langfuse.observation.status_message', body['statusMessage'])
      add_attr(attributes, 'langfuse.environment', body['environment'])

      if obs_type == 'generation'
        add_generation_attributes(attributes, body)
      end

      attributes
    end

    # Add generation-specific gen_ai.* attributes.
    def add_generation_attributes(attributes, body)
      add_attr(attributes, 'gen_ai.request.model', body['model'])

      model_params = body['modelParameters']
      if model_params.is_a?(Hash)
        model_params.each do |key, value|
          add_attr(attributes, "gen_ai.request.#{key}", value) unless value.nil?
        end
      end

      usage = body['usage']
      if usage.is_a?(Hash)
        add_attr(attributes, 'gen_ai.usage.prompt_tokens', usage['promptTokens'] || usage['prompt_tokens'])
        add_attr(attributes, 'gen_ai.usage.completion_tokens', usage['completionTokens'] || usage['completion_tokens'])
        total = usage['totalTokens'] || usage['total_tokens']
        add_attr(attributes, 'gen_ai.usage.total_tokens', total) if total
      end

      add_json_attr(attributes, 'langfuse.observation.usage_details', body['usageDetails'])
      add_json_attr(attributes, 'langfuse.observation.cost_details', body['costDetails'])
      add_attr(attributes, 'langfuse.observation.prompt.name', body['promptName'])
      add_attr(attributes, 'langfuse.observation.prompt.version', body['promptVersion'])
      add_attr(attributes, 'langfuse.observation.completion_start_time', body['completionStartTime'])
    end

    def to_otel_trace_id(id_str)
      self.class.to_otel_trace_id(id_str)
    end

    def to_otel_span_id(id_str)
      self.class.to_otel_span_id(id_str)
    end

    # Convert an ISO8601 timestamp string to nanoseconds since epoch.
    def to_unix_nano(timestamp_str)
      return '0' unless timestamp_str

      time = Time.parse(timestamp_str.to_s)
      (time.to_f * 1_000_000_000).to_i.to_s
    rescue ArgumentError
      '0'
    end

    # Add a string/numeric attribute to the attributes array.
    def add_attr(attributes, key, value)
      return if value.nil?

      otel_value = case value
                   when String
                     { stringValue: value }
                   when Integer
                     { intValue: value.to_s }
                   when Float
                     { doubleValue: value }
                   when TrueClass, FalseClass
                     { boolValue: value }
                   else
                     { stringValue: value.to_s }
                   end

      attributes << { key: key, value: otel_value }
    end

    # Add a JSON-serialized attribute (for complex objects like input/output).
    def add_json_attr(attributes, key, value)
      return if value.nil?
      return if value.is_a?(Hash) && value.empty?
      return if value.is_a?(Array) && value.empty?

      json_str = value.is_a?(String) ? value : JSON.generate(value)
      attributes << { key: key, value: { stringValue: json_str } }
    end

    # Add an array attribute for tags.
    def add_array_attr(attributes, key, values)
      return if values.nil? || values.empty?

      array_values = values.map { |v| { stringValue: v.to_s } }
      attributes << { key: key, value: { arrayValue: { values: array_values } } }
    end
  end
end
