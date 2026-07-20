# frozen_string_literal: true

require 'faraday'
require 'faraday/net_http'
require 'faraday/multipart'
require 'json'
require 'base64'
require 'concurrent'
require 'logger'
require 'digest'

module Langfuse
  class Client
    # The ingestion API limits batch payloads to 3.5 MB in total
    MAX_BATCH_SIZE_BYTES = 3_500_000

    # Allowed format for the tracing environment field
    ENVIRONMENT_PATTERN = /\A(?!langfuse)[a-z0-9\-_]{1,40}\z/

    # Log device that resolves $stdout at write time so output redirection
    # (e.g. in tests) keeps working after the logger was created.
    class StdoutLogDevice
      def write(message)
        $stdout.write(message)
      end

      def close; end
    end

    attr_reader :public_key, :secret_key, :host, :debug, :timeout, :retries, :flush_interval, :auto_flush,
                :ingestion_mode, :environment, :sample_rate, :flush_at, :mask, :logger

    def initialize(public_key: nil, secret_key: nil, host: nil, debug: false, timeout: 30, retries: 3,
                   flush_interval: nil, auto_flush: nil, ingestion_mode: nil, environment: nil,
                   sample_rate: nil, mask: nil, flush_at: nil, logger: nil, shutdown_on_exit: nil)
      @public_key = config_value(public_key, 'LANGFUSE_PUBLIC_KEY', :public_key)
      @secret_key = config_value(secret_key, 'LANGFUSE_SECRET_KEY', :secret_key)
      @host = host || ENV['LANGFUSE_HOST'] || ENV['LANGFUSE_BASE_URL'] || Langfuse.configuration.host
      @debug = debug || ENV['LANGFUSE_DEBUG'] == 'true' || Langfuse.configuration.debug
      @timeout = config_value(timeout, nil, :timeout) { 30 }
      @retries = config_value(retries, nil, :retries) { 3 }
      @flush_interval = config_value(flush_interval, 'LANGFUSE_FLUSH_INTERVAL', :flush_interval) { 5 }
      @flush_at = config_value(flush_at, 'LANGFUSE_FLUSH_AT', :flush_at) { 15 }
      @auto_flush = resolve_auto_flush(auto_flush)
      @ingestion_mode = resolve_ingestion_mode(ingestion_mode)
      @logger = logger || Langfuse.configuration.logger || build_default_logger
      @environment = resolve_environment(environment)
      @sample_rate = resolve_sample_rate(sample_rate)
      @mask = resolve_mask(mask)
      @shutdown_on_exit = shutdown_on_exit.nil? ? Langfuse.configuration.shutdown_on_exit : shutdown_on_exit
      @shutdown = false

      raise AuthenticationError, 'Public key is required' unless @public_key
      raise AuthenticationError, 'Secret key is required' unless @secret_key

      @connection = build_connection
      @otel_connection = build_otel_connection if @ingestion_mode == :otel
      @otel_exporter = OtelExporter.new(connection: @otel_connection, debug: @debug, logger: @logger) if @ingestion_mode == :otel
      @event_queue = Concurrent::Array.new
      @flush_mutex = Mutex.new
      @flush_condition = ConditionVariable.new
      @flush_thread = start_flush_thread if @auto_flush
      register_shutdown_hook if @shutdown_on_exit
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

    # Convenience methods for enhanced observation types

    # Create an agent observation (wrapper around span with as_type: 'agent')
    def agent(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
              metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
              version: nil, **kwargs)
      span(
        trace_id: trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::AGENT,
        **kwargs
      )
    end

    # Create a tool observation (wrapper around span with as_type: 'tool')
    def tool(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
             metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
             version: nil, **kwargs)
      span(
        trace_id: trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::TOOL,
        **kwargs
      )
    end

    # Create a chain observation (wrapper around span with as_type: 'chain')
    def chain(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
              metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
              version: nil, **kwargs)
      span(
        trace_id: trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::CHAIN,
        **kwargs
      )
    end

    # Create a retriever observation (wrapper around span with as_type: 'retriever')
    def retriever(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
                  metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
                  version: nil, **kwargs)
      span(
        trace_id: trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::RETRIEVER,
        **kwargs
      )
    end

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

    # Create an evaluator observation (wrapper around span with as_type: 'evaluator')
    def evaluator_obs(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
                      metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
                      version: nil, **kwargs)
      span(
        trace_id: trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::EVALUATOR,
        **kwargs
      )
    end

    # Create a guardrail observation (wrapper around span with as_type: 'guardrail')
    def guardrail(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
                  metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
                  version: nil, **kwargs)
      span(
        trace_id: trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::GUARDRAIL,
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
    def get_prompt(name, version: nil, label: nil, cache_ttl_seconds: 60)
      cache_key = "prompt:#{name}:#{version}:#{label}"

      if (cached_prompt = @prompt_cache&.dig(cache_key)) && (Time.now - cached_prompt[:cached_at] < cache_ttl_seconds)
        return cached_prompt[:prompt]
      end

      encoded_name = Utils.url_encode(name)
      path = "/api/public/v2/prompts/#{encoded_name}"
      params = {}
      params[:version] = version if version
      params[:label] = label if label

      @logger.debug("Making request to: #{@host}#{path} with params: #{params}")

      response = get(path, params)

      @logger.debug("Response status: #{response.status}")
      @logger.debug("Response headers: #{response.headers}")
      @logger.debug("Response body type: #{response.body.class}")

      # Check if response body is a string (HTML) instead of parsed JSON
      if response.body.is_a?(String) && response.body.include?('<!DOCTYPE html>')
        @logger.debug('Received HTML response instead of JSON:')
        @logger.debug(response.body[0..200])
        raise APIError,
              'Received HTML response instead of JSON. This usually indicates a 404 error or incorrect API endpoint.'
      end

      prompt = Prompt.new(response.body)

      # Cache the prompt
      @prompt_cache ||= {}
      @prompt_cache[cache_key] = { prompt: prompt, cached_at: Time.now }

      prompt
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
    def enqueue_event(type, body)
      # 验证事件类型是否有效
      valid_types = %w[
        trace-create trace-update
        generation-create generation-update
        span-create span-update
        event-create
        score-create
      ]

      unless valid_types.include?(type)
        @logger.debug("Warning: Invalid event type '#{type}'. Skipping event.")
        return
      end

      prepared_body = Utils.prepare_event_body(body)
      inject_default_environment(prepared_body)
      apply_mask(prepared_body)

      return unless sampled_event?(type, prepared_body)

      event = {
        id: Utils.generate_id,
        type: type,
        timestamp: Utils.current_timestamp,
        body: prepared_body
      }

      if type == 'trace-update'
        # 查找对应的 trace-create 事件并更新
        trace_id = body['id'] || body[:id]
        if trace_id
          existing_event_index = @event_queue.find_index do |existing_event|
            existing_event[:type] == 'trace-create' &&
              (existing_event[:body]['id'] == trace_id || existing_event[:body][:id] == trace_id)
          end

          if existing_event_index
            # 更新现有的 trace-create 事件
            @event_queue[existing_event_index][:body].merge!(event[:body])
            @event_queue[existing_event_index][:timestamp] = event[:timestamp]
            @logger.debug("Updated existing trace-create event for trace_id: #{trace_id}")
          else
            # 如果没找到对应的 trace-create 事件，将 trace-update 转换为 trace-create
            event[:type] = 'trace-create'
            @event_queue << event
            @logger.debug("Converted trace-update to trace-create for trace_id: #{trace_id}")
          end
        else
          @logger.debug('Warning: trace-update event missing trace_id, skipping')
        end
      else
        @event_queue << event
      end
      @logger.debug("Enqueued event: #{type}")

      request_flush if @auto_flush && @event_queue.length >= @flush_at
    end

    def flush
      return if @event_queue.empty?

      events = @event_queue.shift(@event_queue.length)
      return if events.empty?

      send_batch(events)
    end

    def shutdown
      return if @shutdown

      @shutdown = true
      @flush_thread&.kill if @auto_flush
      flush unless @event_queue.empty?
    end

    private

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
        return env_val.to_i if env_val && %i[flush_interval flush_at timeout retries].include?(config_attr)
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
      chunks = chunk_events(valid_events)
      response = nil

      chunks.each_with_index do |chunk, index|
        batch_data = build_batch_data(chunk)
        @logger.debug("Sending batch data: #{batch_data}")

        begin
          response = post('/api/public/ingestion', batch_data)
          log_ingestion_errors(response)
          @logger.debug("Flushed #{chunk.length} events (legacy)")
        rescue StandardError => e
          @logger.debug("Failed to flush events: #{e.message}")
          chunks[index..].each { |failed_chunk| failed_chunk.each { |event| @event_queue << event } }
          raise
        end
      end

      response
    end

    def send_batch_otel(valid_events)
      score_events, otel_events = valid_events.partition { |event| event[:type] == 'score-create' }

      response = nil

      unless otel_events.empty?
        @logger.debug("Sending #{otel_events.length} events via OTEL")

        begin
          response = @otel_exporter.export(otel_events)
          handle_response(response)
          @logger.debug("Flushed #{otel_events.length} events (otel)")
        rescue StandardError => e
          @logger.debug("Failed to flush OTEL events: #{e.message}")
          # Re-queue both OTEL and score events — scores were already drained
          # from the queue by flush and would otherwise be permanently lost.
          otel_events.each { |event| @event_queue << event }
          score_events.each { |event| @event_queue << event }
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

      Thread.new do
        loop do
          # Wait for the flush interval or an early wake-up (flush_at threshold)
          @flush_mutex.synchronize { @flush_condition.wait(@flush_mutex, @flush_interval) }
          begin
            flush unless @event_queue.empty?
          rescue StandardError => e
            @logger.debug("Error in flush thread: #{e.message}")
          end
        end
      end
    end

    def resolve_ingestion_mode(explicit_mode)
      return explicit_mode.to_sym if explicit_mode

      env_mode = ENV.fetch('LANGFUSE_INGESTION_MODE', nil)
      return env_mode.to_sym if env_mode && !env_mode.empty?

      Langfuse.configuration.ingestion_mode || :legacy
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

        # 使用默认适配器
        conn.adapter Faraday.default_adapter
      end
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
        conn.adapter Faraday.default_adapter
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

    def request(method, path, params: {}, json: nil)
      retries_left = @retries

      begin
        response = @connection.send(method) do |req|
          req.url path
          req.params = params if params.any?
          req.body = json if json
        end

        handle_response(response)
      rescue Faraday::TimeoutError => e
        raise TimeoutError, "Request timed out: #{e.message}"
      rescue Faraday::ConnectionFailed => e
        if retries_left.positive?
          retries_left -= 1
          sleep(2**(@retries - retries_left))
          retry
        end
        raise NetworkError, "Connection failed: #{e.message}"
      rescue StandardError => e
        raise APIError, "Request failed: #{e.message}"
      end
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
