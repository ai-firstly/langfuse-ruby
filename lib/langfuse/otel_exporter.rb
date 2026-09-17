# frozen_string_literal: true

require 'json'
require 'securerandom'

module Langfuse
  # Converts batched Langfuse events into OTLP/HTTP JSON (ExportTraceServiceRequest)
  # and sends them to the Langfuse OTEL endpoint for v4-compatible ingestion.
  class OtelExporter
    OTEL_ENDPOINT = '/api/public/otel/v1/traces'

    # Event types that carry the full state of an observation on every emit, so a
    # later event supersedes the earlier one for the same observation id.
    OBSERVATION_EVENT_TYPES = %w[span-create span-update generation-create generation-update].freeze

    # Token keys accepted on the legacy `usage` object, in priority order.
    USAGE_INPUT_KEYS = %w[promptTokens prompt_tokens inputTokens input_tokens input].freeze
    USAGE_OUTPUT_KEYS = %w[completionTokens completion_tokens outputTokens output_tokens output].freeze
    USAGE_TOTAL_KEYS = %w[totalTokens total_tokens total].freeze

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
      grouped = group_events_by_trace(collapse_observation_events(events))

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

    # Collapse the create/update events of one observation into a single event.
    # The v4 data model is append-only, so exporting both would produce two
    # observations sharing a span id. Bodies are merged into new hashes, leaving
    # the queued events untouched for re-queueing when the export fails.
    def collapse_observation_events(events)
      position_by_id = {}

      events.each_with_object([]) do |event, collapsed|
        id = observation_event_id(event)

        if id.nil?
          collapsed << event
        elsif (position = position_by_id[id])
          previous = collapsed[position]
          collapsed[position] = previous.merge(
            type: event[:type],
            body: previous[:body].merge(event[:body])
          )
        else
          position_by_id[id] = collapsed.length
          collapsed << event
        end
      end
    end

    def observation_event_id(event)
      return nil unless OBSERVATION_EVENT_TYPES.include?(event[:type])

      body = event[:body]
      return nil unless body.is_a?(Hash)

      body['id'] || body[:id]
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

      add_usage_attributes(attributes, body)
      add_json_attr(attributes, 'langfuse.observation.cost_details', body['costDetails'])
      add_attr(attributes, 'langfuse.observation.prompt.name', body['promptName'])
      add_attr(attributes, 'langfuse.observation.prompt.version', body['promptVersion'])
      add_attr(attributes, 'langfuse.observation.completion_start_time', body['completionStartTime'])
    end

    # Emit token usage both as gen_ai.* semantic conventions and as the Langfuse
    # v4 usage_details model. usage_details is what v4 uses for cost, so a legacy
    # `usage` object is normalized into it when no explicit usage_details exists.
    def add_usage_attributes(attributes, body)
      usage = normalize_legacy_usage(body['usage'])

      if usage
        add_attr(attributes, 'gen_ai.usage.prompt_tokens', usage[:input])
        add_attr(attributes, 'gen_ai.usage.completion_tokens', usage[:output])
        add_attr(attributes, 'gen_ai.usage.total_tokens', usage[:total])
      end

      usage_details = body['usageDetails']
      usage_details = usage if blank_value?(usage_details)
      add_json_attr(attributes, 'langfuse.observation.usage_details', usage_details)
    end

    # Accept every shape the legacy ingestion API allowed
    # (promptTokens / inputTokens / input) and return {input:, output:, total:}.
    # Non-token units are skipped: usage_details is token-based, so mapping them
    # would produce wrong cost numbers.
    def normalize_legacy_usage(usage)
      return nil unless usage.is_a?(Hash) && !usage.empty?

      unit = usage['unit'] || usage[:unit]
      if unit && unit.to_s.upcase != 'TOKENS'
        log_debug { "Skipping usage with unit #{unit}; use usage_details for non-token usage" }
        return nil
      end

      normalized = {
        input: fetch_usage_value(usage, USAGE_INPUT_KEYS),
        output: fetch_usage_value(usage, USAGE_OUTPUT_KEYS),
        total: fetch_usage_value(usage, USAGE_TOTAL_KEYS)
      }.compact

      normalized.empty? ? nil : normalized
    end

    def fetch_usage_value(usage, keys)
      keys.each do |key|
        value = usage[key]
        return value unless value.nil?
      end

      nil
    end

    def blank_value?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
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
      (time.to_i * 1_000_000_000 + time.nsec).to_s
    rescue ArgumentError
      '0'
    end

    # Add a string/numeric attribute to the attributes array.
    # Structured values are JSON-encoded instead of falling back to Ruby's
    # inspect format (which is not machine-readable on the Langfuse side).
    def add_attr(attributes, key, value)
      return if value.nil?
      return add_json_attr(attributes, key, value) if value.is_a?(Hash) || value.is_a?(Array)

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
