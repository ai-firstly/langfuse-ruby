# frozen_string_literal: true

require 'faraday'
require 'faraday/net_http'
require 'faraday/multipart'
require 'json'
require 'base64'
require 'concurrent'
require 'logger'
require 'digest'
require 'time'

module Langfuse
  class Client
    # The ingestion API limits batch payloads to 3.5 MB in total
    MAX_BATCH_SIZE_BYTES = 3_500_000

    # Allowed format for the tracing environment field
    ENVIRONMENT_PATTERN = /\A(?!langfuse)[a-z0-9\-_]{1,40}\z/

    # How long shutdown waits for the flush thread to finish its current send
    FLUSH_THREAD_JOIN_TIMEOUT = 5

    # Dropped-event warnings are emitted on the first drop and then every N drops
    DROPPED_EVENTS_WARN_INTERVAL = 100

    # Supported ingestion transports: the legacy ingestion API and OTLP (Langfuse v4)
    INGESTION_MODES = %i[legacy otel].freeze

    # Backoff for transient request failures. The delay is jittered so that many
    # clients hitting the same rate limit do not retry in lockstep, and capped so
    # a server-sent Retry-After cannot stall a flush for minutes.
    RETRY_BASE_DELAY_SECONDS = 0.5
    MAX_RETRY_DELAY_SECONDS = 10

    # Log device that resolves $stdout at write time so output redirection
    # (e.g. in tests) keeps working after the logger was created.
    class StdoutLogDevice
      def write(message)
        $stdout.write(message)
      end

      def close; end

      def flush
        $stdout.flush
      end
    end

    attr_reader :public_key, :secret_key, :host, :debug, :timeout, :retries, :flush_interval, :auto_flush,
                :ingestion_mode, :environment, :sample_rate, :flush_at, :max_queue_size, :mask, :logger

    # timeout/retries default to nil so that Langfuse.configure values are not
    # shadowed by the method defaults; the fallbacks live in config_value.
    def initialize(public_key: nil, secret_key: nil, host: nil, debug: false, timeout: nil, retries: nil,
                   flush_interval: nil, auto_flush: nil, ingestion_mode: nil, environment: nil,
                   sample_rate: nil, mask: nil, flush_at: nil, max_queue_size: nil, logger: nil,
                   shutdown_on_exit: nil, http_adapter: nil)
      @public_key = config_value(public_key, 'LANGFUSE_PUBLIC_KEY', :public_key)
      @secret_key = config_value(secret_key, 'LANGFUSE_SECRET_KEY', :secret_key)
      @host = host || ENV['LANGFUSE_HOST'] || ENV['LANGFUSE_BASE_URL'] || Langfuse.configuration.host
      @debug = debug || ENV['LANGFUSE_DEBUG'] == 'true' || Langfuse.configuration.debug
      @timeout = config_value(timeout, nil, :timeout) { 30 }
      @retries = config_value(retries, nil, :retries) { 3 }
      @flush_interval = config_value(flush_interval, 'LANGFUSE_FLUSH_INTERVAL', :flush_interval) { 5 }
      @flush_at = config_value(flush_at, 'LANGFUSE_FLUSH_AT', :flush_at) { 15 }
      @max_queue_size = config_value(max_queue_size, 'LANGFUSE_MAX_QUEUE_SIZE', :max_queue_size) { 10_000 }
      @auto_flush = resolve_auto_flush(auto_flush)
      @logger = logger || Langfuse.configuration.logger || build_default_logger
      @ingestion_mode = resolve_ingestion_mode(ingestion_mode)
      @environment = resolve_environment(environment)
      @sample_rate = resolve_sample_rate(sample_rate)
      @mask = resolve_mask(mask)
      @shutdown_on_exit = shutdown_on_exit.nil? ? Langfuse.configuration.shutdown_on_exit : shutdown_on_exit
      @http_adapter = http_adapter || Langfuse.configuration.http_adapter
      @shutdown = false

      raise AuthenticationError, 'Public key is required' unless @public_key
      raise AuthenticationError, 'Secret key is required' unless @secret_key

      setup_transport
      @event_queue = Concurrent::Array.new
      @queue_mutex = Mutex.new
      @flush_mutex = Mutex.new
      @flush_condition = ConditionVariable.new
      @dropped_events = 0
      @prompt_cache = PromptCache.new
      start_flush_thread if @auto_flush
      register_shutdown_hook if @shutdown_on_exit
    end

    # Keep the secret key out of logs, console output and exception messages.
    def inspect
      "#<#{self.class.name} host=#{@host.inspect} public_key=#{@public_key.inspect} " \
        "ingestion_mode=#{@ingestion_mode.inspect}>"
    end

    # Generate a trace ID matching the active ingestion mode
    # (W3C 32-char hex for :otel, UUID for :legacy)
    def generate_trace_id
      @ingestion_mode == :otel ? Utils.generate_hex_trace_id : Utils.generate_id
    end

    # Generate an observation ID matching the active ingestion mode
    # (W3C 16-char hex for :otel, UUID for :legacy)
    def generate_observation_id
      @ingestion_mode == :otel ? Utils.generate_hex_span_id : Utils.generate_id
    end

    # Trace operations
    def trace(id: nil, name: nil, user_id: nil, session_id: nil, version: nil, release: nil,
              input: nil, output: nil, metadata: nil, tags: nil, timestamp: nil, **kwargs)
      Trace.new(
        client: self,
        id: id || generate_trace_id,
        name: name,
        user_id: user_id,
        session_id: session_id,
        version: version,
        release: release,
        input: input,
        output: output,
        metadata: metadata,
        tags: tags,
        timestamp: timestamp || Utils.current_timestamp,
        **kwargs
      )
    end

    # Span operations
    def span(trace_id:, id: nil, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
             metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
             version: nil, as_type: nil, **kwargs)
      Span.new(
        client: self,
        trace_id: trace_id,
        id: id || generate_observation_id,
        name: name,
        start_time: start_time || Utils.current_timestamp,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: as_type,
        **kwargs
      )
    end

    # Convenience methods for enhanced observation types: each is a span with a
    # fixed as_type. (embedding keeps its own definition because it folds
    # model/usage into metadata first.)
    extend SpanWrappers
    define_span_wrappers(evaluator_name: :evaluator_obs)

    # `evaluator` matches Trace/Span/Generation; `evaluator_obs` is kept for
    # callers that adopted the older name.
    alias evaluator evaluator_obs

    # Create an embedding observation (wrapper around span with as_type: 'embedding')
    def embedding(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
                  model: nil, usage: nil, metadata: nil, level: nil, status_message: nil,
                  parent_observation_id: nil, version: nil, **kwargs)
      merged_metadata = (metadata || {}).merge(
        { model: model, usage: usage }.compact
      )
      span(
        trace_id: trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: merged_metadata.empty? ? nil : merged_metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::EMBEDDING,
        **kwargs
      )
    end

    # Generation operations
    def generation(trace_id:, id: nil, name: nil, start_time: nil, end_time: nil, completion_start_time: nil,
                   model: nil, model_parameters: nil, input: nil, output: nil, usage: nil,
                   usage_details: nil, cost_details: nil, prompt: nil,
                   metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
                   version: nil, **kwargs)
      Generation.new(
        client: self,
        trace_id: trace_id,
        id: id || generate_observation_id,
        name: name,
        start_time: start_time || Utils.current_timestamp,
        end_time: end_time,
        completion_start_time: completion_start_time,
        model: model,
        model_parameters: model_parameters,
        input: input,
        output: output,
        usage: usage,
        usage_details: usage_details,
        cost_details: cost_details,
        prompt: prompt,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        **kwargs
      )
    end

    # Event operations
    def event(trace_id:, name:, id: nil, start_time: nil, input: nil, output: nil, metadata: nil,
              level: nil, status_message: nil, parent_observation_id: nil, version: nil, **kwargs)
      Event.new(
        client: self,
        trace_id: trace_id,
        id: id || generate_observation_id,
        name: name,
        start_time: start_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        **kwargs
      )
    end

    # Prompt operations
    def get_prompt(name, version: nil, label: nil, cache_ttl_seconds: 60, retries: nil)
      cache_key = "prompt:#{name}:#{version}:#{label}"
      cached = @prompt_cache.read(cache_key, cache_ttl_seconds)
      return cached if cached

      begin
        prompt = request_prompt(name, version: version, label: label, retries: retries)
      rescue StandardError => e
        # An expired entry beats no prompt at all: serving it keeps the
        # application running through a Langfuse outage.
        stale = @prompt_cache.read_stale(cache_key)
        raise unless stale

        @logger.warn("Langfuse prompt fetch failed (#{name}), serving the cached copy: #{e.message}")
        return stale
      end

      @prompt_cache.write(cache_key, prompt)
    end

    def create_prompt(name:, prompt:, labels: [], config: {}, **kwargs)
      data = {
        name: name,
        prompt: prompt,
        labels: labels,
        config: config,
        **kwargs
      }

      response = post('/api/public/v2/prompts', data)
      Prompt.new(response.body)
    end

    # Score/Evaluation operations
    # Scores can target a trace, an observation (trace_id + observation_id),
    # a session (session_id) or a dataset run (dataset_run_id).
    def score(name:, value:, trace_id: nil, observation_id: nil, session_id: nil, dataset_run_id: nil,
              id: nil, data_type: nil, comment: nil, metadata: nil, config_id: nil, queue_id: nil,
              environment: nil, **kwargs)
      data = {
        id: id,
        trace_id: trace_id,
        observation_id: observation_id,
        session_id: session_id,
        dataset_run_id: dataset_run_id,
        name: name,
        value: value,
        data_type: data_type,
        comment: comment,
        metadata: metadata,
        config_id: config_id,
        queue_id: queue_id,
        environment: environment,
        **kwargs
      }.compact

      if trace_id.nil? && observation_id.nil? && session_id.nil? && dataset_run_id.nil?
        @logger.warn('Langfuse score should reference a trace_id, observation_id, session_id or dataset_run_id')
      end

      enqueue_event('score-create', data)
    end
    alias create_score score

    # Event queue management
    def enqueue_event(type, body, trace_ref: nil)
      # 验证事件类型是否有效
      valid_types = %w[
        trace-create trace-update
        generation-create generation-update
        span-create span-update
        event-create
        score-create
      ]

      unless valid_types.include?(type)
        @logger.debug { "Warning: Invalid event type '#{type}'. Skipping event." }
        return
      end

      # Runs before the event is queued so events inherited from a parent process
      # are discarded without dropping the event we are about to enqueue.
      ensure_flush_thread

      prepared_body = prepare_queued_body(body)

      return unless sampled_event?(type, prepared_body)

      event = {
        id: Utils.generate_id,
        type: type,
        timestamp: Utils.current_timestamp,
        body: prepared_body
      }
      event[:trace_ref] = trace_ref if trace_ref

      # The queue is drained under the same lock, so a concurrent flush can no
      # longer take an event out between finding it and merging into it.
      queued = @queue_mutex.synchronize do
        if type == 'trace-update'
          merge_or_queue_trace_update?(event)
        else
          push_event?(event)
        end
      end
      return unless queued

      @logger.debug { "Enqueued event: #{type}" }

      request_flush if @auto_flush && @event_queue.length >= @flush_at
    end

    def flush
      events = @queue_mutex.synchronize do
        @event_queue.empty? ? [] : @event_queue.shift(@event_queue.length)
      end
      return if events.empty?

      send_batch(events)
    end

    def shutdown
      return if @shutdown

      @shutdown = true
      stop_flush_thread
      flush unless @event_queue.empty?
    end

    private

    def setup_transport
      @connection = build_connection
      return unless @ingestion_mode == :otel

      @otel_connection = build_otel_connection
      @otel_exporter = OtelExporter.new(connection: @otel_connection, debug: @debug, logger: @logger)
    end

    def request_prompt(name, version:, label:, retries: nil)
      path = "/api/public/v2/prompts/#{Utils.url_encode(name)}"
      params = {}
      params[:version] = version if version
      params[:label] = label if label

      @logger.debug { "Making request to: #{@host}#{path} with params: #{params}" }

      response = request(:get, path, params: params, retries: retries)

      @logger.debug { "Response status: #{response.status}, body type: #{response.body.class}" }

      # Check if response body is a string (HTML) instead of parsed JSON
      if response.body.is_a?(String) && response.body.include?('<!DOCTYPE html>')
        @logger.debug { "Received HTML response instead of JSON: #{response.body[0..200]}" }
        raise APIError,
              'Received HTML response instead of JSON. This usually indicates a 404 error or incorrect API endpoint.'
      end

      Prompt.new(response.body)
    end

    def build_default_logger
      logger = Logger.new(StdoutLogDevice.new)
      logger.level = @debug ? Logger::DEBUG : Logger::WARN
      logger.progname = 'langfuse'
      logger.formatter = proc do |severity, _time, progname, msg|
        "#{severity} -- #{progname}: #{msg}\n"
      end
      logger
    end

    # Resolve a config value with precedence: explicit arg > env var > config attr > block default
    def config_value(explicit, env_key, config_attr)
      return explicit if explicit

      if env_key
        env_val = ENV.fetch(env_key, nil)
        if env_val && %i[flush_interval flush_at timeout retries max_queue_size].include?(config_attr)
          return env_val.to_i
        end

        return env_val if env_val
      end

      Langfuse.configuration.send(config_attr) || (yield if block_given?)
    end

    def resolve_auto_flush(auto_flush)
      if auto_flush.nil?
        ENV['LANGFUSE_AUTO_FLUSH'] == 'false' ? false : Langfuse.configuration.auto_flush
      else
        auto_flush
      end
    end

    def resolve_environment(explicit_environment)
      environment = explicit_environment || ENV['LANGFUSE_TRACING_ENVIRONMENT'] || Langfuse.configuration.environment
      return nil if environment.nil? || environment.to_s.empty?

      environment = environment.to_s
      unless environment.match?(ENVIRONMENT_PATTERN)
        @logger.warn("Invalid Langfuse environment '#{environment}'. It must match #{ENVIRONMENT_PATTERN.inspect}. " \
                     'Events may be rejected by the server.')
      end
      environment
    end

    def resolve_sample_rate(explicit_sample_rate)
      rate = explicit_sample_rate || ENV['LANGFUSE_SAMPLE_RATE']&.to_f || Langfuse.configuration.sample_rate
      return nil if rate.nil?

      rate = rate.to_f
      unless rate.between?(0.0, 1.0)
        @logger.warn("Invalid Langfuse sample_rate #{rate}, expected 0.0..1.0. Disabling sampling.")
        return nil
      end
      rate
    end

    def resolve_mask(explicit_mask)
      mask = explicit_mask || Langfuse.configuration.mask
      return nil if mask.nil?

      unless mask.respond_to?(:call)
        @logger.warn('Langfuse mask must respond to #call. Ignoring mask.')
        return nil
      end
      mask
    end

    def register_shutdown_hook
      at_exit do
        shutdown
      rescue StandardError => e
        @logger.debug("Langfuse shutdown on exit failed: #{e.message}")
      end
    end

    # Camelize top-level keys, inject the default environment, then apply the
    # mask. Every body that enters the queue — including a trace_ref rebuilt
    # after the matching create has already flushed — must go through this.
    def prepare_queued_body(body)
      prepared = Utils.prepare_event_body(body)
      inject_default_environment(prepared)
      apply_mask(prepared)
      prepared
    end

    def inject_default_environment(body)
      return unless @environment
      return if body.key?('environment')

      body['environment'] = @environment
    end

    def apply_mask(body)
      return unless @mask

      %w[input output metadata].each do |field|
        next unless body.key?(field) && !body[field].nil?

        body[field] = begin
          @mask.call(body[field])
        rescue StandardError => e
          @logger.error("Langfuse mask function failed: #{e.message}")
          '<masked due to failed mask function>'
        end
      end
    end

    # Deterministic trace-based sampling: all events of a trace share the same decision.
    def sampled_event?(type, body)
      return true unless @sample_rate

      trace_id = %w[trace-create trace-update].include?(type) ? body['id'] : body['traceId']
      return true if trace_id.nil?

      return true if trace_sampled?(trace_id)

      @logger.debug("Dropping event for trace #{trace_id} due to sampling (rate: #{@sample_rate})")
      false
    end

    def trace_sampled?(trace_id)
      return true if @sample_rate >= 1.0
      return false if @sample_rate <= 0.0

      normalized = Digest::SHA256.hexdigest(trace_id.to_s)[0, 8].to_i(16).to_f / 0xffffffff
      normalized < @sample_rate
    end

    def request_flush
      @flush_mutex.synchronize { @flush_condition.signal }
    end

    # Merge a trace-update into the queued trace-create for the same trace.
    # Returns whether the queue changed. Callers must hold @queue_mutex.
    def merge_or_queue_trace_update?(event)
      trace_id = event[:body]['id']

      unless trace_id
        @logger.debug { 'Warning: trace-update event missing trace_id, skipping' }
        return false
      end

      position = @event_queue.find_index do |queued_event|
        queued_event[:type] == 'trace-create' && queued_event[:body]['id'] == trace_id
      end

      unless position
        # Nothing left to merge into (already flushed): send it as a create so
        # the server can upsert. Use the trace's full state (via :trace_ref) to
        # avoid sending a partial body that would produce a broken observation.
        event[:type] = 'trace-create'
        if event[:trace_ref]
          # to_dict is the live instance state (symbol keys, unmasked). Re-run
          # the same prepare/env/mask path as enqueue_event so the API still
          # sees camelCase keys, the default environment, and redacted PII.
          event[:body] = prepare_queued_body(event[:trace_ref].to_dict)
          event.delete(:trace_ref)
        end
        @logger.debug { "Converted trace-update to trace-create for trace_id: #{trace_id}" }
        return push_event?(event)
      end

      @event_queue[position][:body].merge!(event[:body])
      @event_queue[position][:timestamp] = event[:timestamp]
      @logger.debug { "Updated existing trace-create event for trace_id: #{trace_id}" }
      true
    end

    # Append an event, evicting the oldest ones when the queue is full. Without a
    # bound, an unreachable Langfuse would grow the queue until the process dies.
    # Callers must hold @queue_mutex. Returns whether the event was queued.
    def push_event?(event)
      dropped = 0
      while @event_queue.length >= @max_queue_size
        @event_queue.shift
        dropped += 1
      end

      if dropped.positive?
        @dropped_events += dropped
        warn_dropped_events
      end

      @event_queue << event
      true
    end

    def warn_dropped_events
      return unless @dropped_events == 1 || (@dropped_events % DROPPED_EVENTS_WARN_INTERVAL).zero?

      @logger.warn("Langfuse event queue is full (max_queue_size=#{@max_queue_size}); " \
                   "dropped #{@dropped_events} oldest events so far")
    end

    # Put events back for the next flush. Permanent failures are dropped instead:
    # they would fail again on every flush and block the queue indefinitely.
    # Events are prepended so they are retried before any newly enqueued events,
    # preserving the original chronological order.
    def requeue_events(events, error)
      return if events.empty?

      if permanent_failure?(error)
        @logger.warn("Langfuse dropped #{events.length} events after a permanent failure " \
                     "(#{error.class}): #{error.message}")
        return
      end

      @queue_mutex.synchronize { events.reverse_each { |event| prepend_event(event) } }
    end

    # Insert an event at the head of the queue, evicting the oldest (tail) if full.
    # Callers must hold @queue_mutex.
    def prepend_event(event)
      if @event_queue.length >= @max_queue_size
        @event_queue.pop
        @dropped_events += 1
        warn_dropped_events
      end
      @event_queue.unshift(event)
    end

    def permanent_failure?(error)
      error.is_a?(ValidationError) || error.is_a?(AuthenticationError)
    end

    # Threads do not survive fork. Recreate the flush thread in the child and drop
    # the events it inherited, which the parent process still flushes itself.
    def ensure_flush_thread
      return unless @auto_flush
      return if @flush_thread_pid == Process.pid && @flush_thread&.alive?

      if @flush_thread_pid && @flush_thread_pid != Process.pid
        inherited = @queue_mutex.synchronize { @event_queue.shift(@event_queue.length) }
        @logger.debug { "Dropped #{inherited.length} events inherited from pid #{@flush_thread_pid}" }
      end

      start_flush_thread
    end

    # Let the flush thread finish the send it is in the middle of; killing it
    # would lose the events it already drained from the queue.
    def stop_flush_thread
      thread = @flush_thread
      return unless thread

      @stop_flushing = true
      @flush_thread = nil
      request_flush
      return if thread.join(FLUSH_THREAD_JOIN_TIMEOUT)

      @logger.warn("Langfuse flush thread did not stop within #{FLUSH_THREAD_JOIN_TIMEOUT}s; terminating it")
      thread.kill
    end

    def debug_event_data(events)
      return unless @debug

      @logger.debug('=== Event Data Debug Information ===')
      events.each_with_index do |event, index|
        @logger.debug("Event #{index + 1}:")
        @logger.debug("  ID: #{event[:id]}")
        @logger.debug("  Type: #{event[:type]}")
        @logger.debug("  Timestamp: #{event[:timestamp]}")
        @logger.debug("  Body keys: #{event[:body]&.keys || 'nil'}")

        # 检查常见的问题
        @logger.debug('  ⚠️  WARNING: Empty or nil type!') if event[:type].nil? || event[:type].to_s.empty?

        @logger.debug('  ⚠️  WARNING: Empty body!') if event[:body].nil?

        @logger.debug('  ---')
      end
      @logger.debug('=== End Debug Information ===')
    end

    def send_batch(events)
      # 调试事件数据
      debug_event_data(events)

      # 验证事件数据
      valid_events = events.select do |event|
        if event[:type].nil? || event[:type].to_s.empty?
          @logger.debug("Warning: Event with empty type detected, skipping: #{event[:id]}")
          false
        elsif event[:body].nil?
          @logger.debug("Warning: Event with empty body detected, skipping: #{event[:id]}")
          false
        else
          true
        end
      end

      if valid_events.empty?
        @logger.debug('No valid events to send')
        return
      end

      if @ingestion_mode == :otel
        send_batch_otel(valid_events)
      else
        send_batch_legacy(valid_events)
      end
    end

    def send_batch_legacy(valid_events)
      payload = encode_batch(valid_events)

      # Common case: the whole batch fits, so this single JSON pass covers both
      # the size check and the request body. Only an oversized payload pays for
      # the per-event accounting in chunk_events.
      if payload && payload.bytesize <= MAX_BATCH_SIZE_BYTES
        begin
          return post_ingestion(payload, valid_events.length)
        rescue StandardError => e
          @logger.debug { "Failed to flush events: #{e.message}" }
          requeue_events(valid_events, e)
          raise
        end
      end

      send_batch_legacy_chunked(valid_events)
    end

    def send_batch_legacy_chunked(valid_events)
      chunks = chunk_events(valid_events)
      response = nil

      chunks.each_with_index do |chunk, index|
        response = post_ingestion(encode_batch(chunk) || build_batch_data(chunk), chunk.length)
      rescue StandardError => e
        @logger.debug { "Failed to flush events: #{e.message}" }
        requeue_events(chunks[index..].flatten(1), e)
        raise
      end

      response
    end

    # Faraday forwards a String body untouched, so a pre-serialized batch is not
    # encoded a second time by the JSON middleware.
    def encode_batch(events)
      JSON.generate(build_batch_data(events))
    rescue StandardError => e
      @logger.debug { "Could not pre-serialize the batch, letting Faraday encode it: #{e.message}" }
      nil
    end

    def post_ingestion(payload, event_count)
      # Block form: interpolating a multi-megabyte batch would cost the same
      # whether or not debug logging is enabled.
      @logger.debug { "Sending batch data: #{payload}" }

      response = post('/api/public/ingestion', payload)
      log_ingestion_errors(response)
      @logger.debug { "Flushed #{event_count} events (legacy)" }
      response
    end

    def send_batch_otel(valid_events)
      score_events, otel_events = valid_events.partition { |event| event[:type] == 'score-create' }

      response = nil

      unless otel_events.empty?
        @logger.debug { "Sending #{otel_events.length} events via OTEL" }
        chunks = chunk_events(otel_events)

        chunks.each_with_index do |chunk, index|
          response = export_otel_chunk(chunk)
        rescue StandardError => e
          @logger.debug { "Failed to flush OTEL events: #{e.message}" }
          # Re-queue the not-yet-sent OTel chunks. Permanent failures (4xx)
          # are dropped by requeue_events; transient ones are re-queued.
          requeue_events(chunks[index..].flatten(1), e)
          # Score events were never attempted and must always be re-queued,
          # regardless of why the OTel chunk failed.
          unless score_events.empty?
            @queue_mutex.synchronize { score_events.each { |ev| prepend_event(ev) } }
          end
          raise
        end
      end

      # Scores are not part of the OTLP trace mapping; they always go through
      # the ingestion API. IDs are normalized to match the OTel-derived IDs.
      unless score_events.empty?
        score_events.each { |event| normalize_otel_score_event(event) }
        response = send_batch_legacy(score_events)
      end

      response
    end

    # Export one chunk of events to the OTLP endpoint with retries for transient errors.
    def export_otel_chunk(chunk, retries: nil)
      allowed_retries = retries || @retries
      attempt = 0
      response = nil

      begin
        response = execute_otel_export(chunk)
        handle_response(response)
        log_otel_partial_success(response)
        @logger.debug { "Flushed #{chunk.length} events (otel)" }
        response
      rescue Langfuse::Error => e
        raise unless attempt < allowed_retries && retryable_error?(e, response)

        attempt += 1
        delay = retry_delay(attempt, response)
        @logger.debug { "Retrying OTEL export in #{delay.round(2)}s (attempt #{attempt}/#{allowed_retries}): #{e.message}" }
        response = nil
        sleep(delay)
        retry
      end
    end

    def execute_otel_export(chunk)
      @otel_exporter.export(chunk)
    rescue Faraday::TimeoutError => e
      raise TimeoutError, "Request timed out: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise NetworkError, "Connection failed: #{e.message}"
    rescue Faraday::Error => e
      raise APIError, "OTEL export failed: #{e.message}"
    end

    # The OTLP endpoint answers 200 even when it rejected part of the payload.
    def log_otel_partial_success(response)
      body = response.respond_to?(:body) ? response.body : nil
      return unless body.is_a?(Hash)

      partial = body['partialSuccess'] || body[:partialSuccess]
      return unless partial.is_a?(Hash)

      rejected = (partial['rejectedSpans'] || partial[:rejectedSpans]).to_i
      message = (partial['errorMessage'] || partial[:errorMessage]).to_s
      return if rejected.zero? && message.empty?

      details = " - #{message}" unless message.empty?
      @logger.warn("Langfuse OTEL partial success: #{rejected} spans rejected#{details}")
    end

    # Align score references with the OTel-derived trace/span IDs so scores
    # attach to the correct entities when ingesting via the OTel endpoint.
    def normalize_otel_score_event(event)
      body = event[:body]
      return unless body.is_a?(Hash)

      body['traceId'] = OtelExporter.to_otel_trace_id(body['traceId']) if body['traceId']
      body['observationId'] = OtelExporter.to_otel_span_id(body['observationId']) if body['observationId']
    end

    # Split events into chunks that respect the ingestion API batch size limit.
    def chunk_events(events)
      chunks = [[]]
      current_size = 0

      events.each do |event|
        event_size = estimated_event_size(event)

        if event_size > MAX_BATCH_SIZE_BYTES
          @logger.warn("Langfuse event #{event[:id]} exceeds the maximum batch size of #{MAX_BATCH_SIZE_BYTES} bytes and was dropped")
          next
        end

        if current_size + event_size > MAX_BATCH_SIZE_BYTES && !chunks.last.empty?
          chunks << []
          current_size = 0
        end

        chunks.last << event
        current_size += event_size
      end

      chunks.reject(&:empty?)
    end

    def estimated_event_size(event)
      JSON.generate(event).bytesize
    rescue StandardError
      1024
    end

    # The ingestion API responds with 207 and per-event successes/errors.
    def log_ingestion_errors(response)
      body = response.respond_to?(:body) ? response.body : nil
      return unless body.is_a?(Hash)

      errors = body['errors']
      return unless errors.is_a?(Array) && errors.any?

      errors.each do |error|
        @logger.warn("Langfuse ingestion partial failure (status #{error['status']}): " \
                     "event #{error['id']} - #{error['message']}")
      end
    end

    def build_batch_data(events)
      {
        batch: events,
        metadata: Utils.deep_camelize_keys({
                                             batch_size: events.length,
                                             sdk_name: 'langfuse-ruby',
                                             sdk_version: Langfuse::VERSION
                                           })
      }
    end

    def start_flush_thread
      return unless @auto_flush

      @stop_flushing = false
      @flush_thread_pid = Process.pid
      @flush_thread = Thread.new do
        until @stop_flushing
          # Wait for the flush interval or an early wake-up (flush_at threshold)
          @flush_mutex.synchronize { @flush_condition.wait(@flush_mutex, @flush_interval) }
          break if @stop_flushing

          begin
            flush unless @event_queue.empty?
          rescue StandardError => e
            @logger.debug { "Error in flush thread: #{e.message}" }
          end
        end
      end
    end

    def resolve_ingestion_mode(explicit_mode)
      env_mode = ENV.fetch('LANGFUSE_INGESTION_MODE', nil)
      env_mode = nil if env_mode&.empty?
      mode = explicit_mode || env_mode || Langfuse.configuration.ingestion_mode
      return :legacy if mode.nil?

      # Unrecognized values used to silently behave like :legacy, so a typo in
      # LANGFUSE_INGESTION_MODE looked like a working v4 setup.
      mode = mode.to_s.downcase.to_sym
      return mode if INGESTION_MODES.include?(mode)

      @logger.warn do
        "Unknown Langfuse ingestion_mode #{mode.inspect}, expected one of #{INGESTION_MODES.join(', ')}. Using :legacy."
      end
      :legacy
    end

    def build_connection
      Faraday.new(url: @host) do |conn|
        # 配置请求和响应处理
        conn.request :json
        conn.response :json, content_type: /\bjson$/

        # 设置 User-Agent 头部
        conn.headers['User-Agent'] = "langfuse-ruby/#{Langfuse::VERSION}"
        # 根据 Langfuse 文档配置 Basic Auth
        # username: Langfuse Public Key, password: Langfuse Secret Key
        conn.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{@public_key}:#{@secret_key}")}"

        # 设置超时
        conn.options.timeout = @timeout

        # 添加调试日志
        conn.response :logger if @debug

        apply_http_adapter(conn)
      end
    end

    # The default net_http adapter opens and closes a connection per request.
    # `http_adapter` lets an application swap in a keep-alive adapter (for
    # example `:net_http_persistent`) without this gem depending on it; an
    # adapter that is not installed falls back instead of breaking tracing.
    def apply_http_adapter(conn)
      return conn.adapter(Faraday.default_adapter) if @http_adapter.nil?

      conn.adapter(*Array(@http_adapter))
    rescue StandardError => e
      @logger.warn("Langfuse could not use the #{@http_adapter.inspect} Faraday adapter " \
                   "(#{e.message}); falling back to #{Faraday.default_adapter.inspect}")
      conn.adapter(Faraday.default_adapter)
    end

    # Build a separate Faraday connection for OTEL with the v4 ingestion header.
    def build_otel_connection
      Faraday.new(url: @host) do |conn|
        conn.response :json, content_type: /\bjson$/

        conn.headers['User-Agent'] = "langfuse-ruby/#{Langfuse::VERSION}"
        conn.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{@public_key}:#{@secret_key}")}"
        conn.headers['x-langfuse-ingestion-version'] = '4'
        conn.headers['Content-Type'] = 'application/json'

        conn.options.timeout = @timeout
        conn.response :logger if @debug
        apply_http_adapter(conn)
      end
    end

    # HTTP methods
    def get(path, params = {})
      request(:get, path, params: params)
    end

    def post(path, data = {})
      request(:post, path, json: data)
    end

    def put(path, data = {})
      request(:put, path, json: data)
    end

    def delete(path, params = {})
      request(:delete, path, params: params)
    end

    def patch(path, data = {})
      request(:patch, path, json: data)
    end

    def request(method, path, params: {}, json: nil, retries: nil)
      allowed_retries = retries || @retries
      attempt = 0
      response = nil

      begin
        response = execute_request(method, path, params, json)
        handle_response(response)
      rescue Langfuse::Error => e
        # Typed errors raised by handle_response (401/404/429/4xx/5xx) keep their
        # class so callers can rescue AuthenticationError/RateLimitError etc.
        raise unless attempt < allowed_retries && retryable_error?(e, response)

        attempt += 1
        delay = retry_delay(attempt, response)
        @logger.debug { "Retrying #{method.upcase} #{path} in #{delay.round(2)}s (attempt #{attempt}/#{allowed_retries}): #{e.message}" }
        response = nil
        sleep(delay)
        retry
      rescue StandardError => e
        raise APIError, "Request failed: #{e.message}"
      end
    end

    def execute_request(method, path, params, json)
      @connection.send(method) do |req|
        req.url path
        req.params = params if params.any?
        req.body = json if json
      end
    rescue Faraday::TimeoutError => e
      raise TimeoutError, "Request timed out: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise NetworkError, "Connection failed: #{e.message}"
    end

    # Transient failures worth another attempt. Authentication and validation
    # errors would fail identically on a retry, so they are raised immediately.
    def retryable_error?(error, response)
      case error
      when TimeoutError, NetworkError, RateLimitError
        true
      when APIError
        response.respond_to?(:status) && response.status >= 500
      else
        false
      end
    end

    # Honor the server's Retry-After when present, otherwise back off
    # exponentially with jitter.
    def retry_delay(attempt, response)
      server_delay = retry_after_seconds(response)
      return server_delay if server_delay

      backoff = [RETRY_BASE_DELAY_SECONDS * (2**(attempt - 1)), MAX_RETRY_DELAY_SECONDS].min
      backoff * (0.5 + (rand * 0.5))
    end

    def retry_after_seconds(response)
      raw = response.respond_to?(:headers) ? response.headers&.[]('retry-after') : nil
      return nil if raw.nil? || raw.to_s.strip.empty?

      seconds = Float(raw, exception: false) || http_date_delay(raw)
      return nil unless seconds

      seconds.clamp(0, MAX_RETRY_DELAY_SECONDS)
    end

    # Retry-After may also be an HTTP date instead of a number of seconds.
    def http_date_delay(raw)
      Time.httpdate(raw.to_s) - Time.now
    rescue ArgumentError
      nil
    end

    def handle_response(response)
      @logger.debug("Handling response with status: #{response.status}")

      case response.status
      when 200..299
        response
      when 401
        raise AuthenticationError, "Authentication failed: #{response.body}"
      when 404
        # 404 错误通常返回 HTML 页面
        error_message = 'Resource not found (404)'
        if response.body.is_a?(String) && response.body.include?('<!DOCTYPE html>')
          error_message += '. Server returned HTML page instead of JSON API response. This usually means the requested resource does not exist.'
        else
          error_message += ": #{response.body}"
        end
        raise ValidationError, error_message
      when 429
        raise RateLimitError, "Rate limit exceeded: #{response.body}"
      when 400..499
        # 为 400 错误提供更详细的错误信息
        error_details = ''
        if response.body.is_a?(Hash) && response.body['error']
          error_details = "\nError details: #{response.body['error']}"
        elsif response.body.is_a?(String)
          error_details = "\nError details: #{response.body}"
        end

        # 特别处理类型验证错误
        unless response.body.to_s.include?('invalid_union') || response.body.to_s.include?('discriminator')
          raise ValidationError, "Client error (#{response.status}): #{response.body}#{error_details}"
        end

        raise ValidationError,
              "Event type validation failed (#{response.status}): The event type or structure is invalid. Please check the event format.#{error_details}"

      when 500..599
        raise APIError, "Server error (#{response.status}): #{response.body}"
      else
        raise APIError, "Unexpected response (#{response.status}): #{response.body}"
      end
    end
  end
end
