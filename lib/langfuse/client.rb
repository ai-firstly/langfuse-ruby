# frozen_string_literal: true

require 'faraday'
require 'faraday/net_http'
require 'faraday/multipart'
require 'json'
require 'base64'
require 'concurrent'

module Langfuse
  class Client
    attr_reader :public_key, :secret_key, :host, :debug, :timeout, :retries, :flush_interval, :auto_flush

    def initialize(public_key: nil, secret_key: nil, host: nil, debug: nil, timeout: 30, retries: 3,
                   flush_interval: nil, auto_flush: nil)
      @public_key = public_key || ENV['LANGFUSE_PUBLIC_KEY'] || Langfuse.configuration.public_key
      @secret_key = secret_key || ENV['LANGFUSE_SECRET_KEY'] || Langfuse.configuration.secret_key
      @host = host || ENV['LANGFUSE_HOST'] || Langfuse.configuration.host
      @debug = debug.nil? ? (ENV['LANGFUSE_DEBUG'] == 'true' || Langfuse.configuration.debug) : debug
      @timeout = timeout || Langfuse.configuration.timeout
      @retries = retries || Langfuse.configuration.retries
      @flush_interval = flush_interval || ENV['LANGFUSE_FLUSH_INTERVAL']&.to_i || Langfuse.configuration.flush_interval
      @auto_flush = if auto_flush.nil?
                      ENV['LANGFUSE_AUTO_FLUSH'] == 'false' ? false : Langfuse.configuration.auto_flush
                    else
                      auto_flush
                    end

      raise AuthenticationError, 'Public key is required' unless @public_key && !@public_key.empty?
      raise AuthenticationError, 'Secret key is required' unless @secret_key && !@secret_key.empty?

      @connection = build_connection
      @event_queue = Concurrent::Array.new
      @flush_thread = start_flush_thread if @auto_flush
    end

    # Trace operations
    def trace(id: nil, name: nil, user_id: nil, session_id: nil, version: nil, release: nil,
              input: nil, output: nil, metadata: nil, tags: nil, timestamp: nil, **kwargs)
      Trace.new(
        client: self,
        id: id || Utils.generate_id,
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
    def span(trace_id:, name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
             metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
             version: nil, as_type: nil, **kwargs)
      Span.new(
        client: self,
        trace_id: trace_id,
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
    def generation(trace_id:, name: nil, start_time: nil, end_time: nil, completion_start_time: nil,
                   model: nil, model_parameters: nil, input: nil, output: nil, usage: nil,
                   metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
                   version: nil, **kwargs)
      Generation.new(
        client: self,
        trace_id: trace_id,
        name: name,
        start_time: start_time || Utils.current_timestamp,
        end_time: end_time,
        completion_start_time: completion_start_time,
        model: model,
        model_parameters: model_parameters,
        input: input,
        output: output,
        usage: usage,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        **kwargs
      )
    end

    # Event operations
    def event(trace_id:, name:, start_time: nil, input: nil, output: nil, metadata: nil,
              level: nil, status_message: nil, parent_observation_id: nil, version: nil, **kwargs)
      Event.new(
        client: self,
        trace_id: trace_id,
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

      puts "Making request to: #{@host}#{path} with params: #{params}" if @debug

      response = get(path, params)

      puts "Response status: #{response.status}" if @debug
      puts "Response headers: #{response.headers}" if @debug
      puts "Response body type: #{response.body.class}" if @debug

      # Check if response body is a string (HTML) instead of parsed JSON
      if response.body.is_a?(String) && response.body.include?('<!DOCTYPE html>')
        puts 'Received HTML response instead of JSON:' if @debug
        puts response.body[0..200] if @debug
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
    def score(name:, value:, trace_id: nil, observation_id: nil, generation_id: nil, span_id: nil, data_type: nil, comment: nil, **kwargs)
      data = {
        name: name,
        value: value,
        data_type: data_type,
        comment: comment,
        **kwargs
      }

      data[:trace_id] = trace_id if trace_id
      data[:observation_id] = observation_id if observation_id
      data[:generation_id] = generation_id if generation_id
      data[:span_id] = span_id if span_id

      enqueue_event('score-create', data)
    end

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
        puts "Warning: Invalid event type '#{type}'. Skipping event." if @debug
        return
      end

      event = {
        id: Utils.generate_id,
        type: type,
        timestamp: Utils.current_timestamp,
        body: Utils.deep_stringify_keys(body)
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
            puts "Updated existing trace-create event for trace_id: #{trace_id}" if @debug
          else
            # 如果没找到对应的 trace-create 事件，将 trace-update 转换为 trace-create
            event[:type] = 'trace-create'
            @event_queue << event
            puts "Converted trace-update to trace-create for trace_id: #{trace_id}" if @debug
          end
        elsif @debug
          puts 'Warning: trace-update event missing trace_id, skipping'
        end
      else
        @event_queue << event
      end
      puts "Enqueued event: #{type}" if @debug
    end

    def flush
      return if @event_queue.empty?

      events = @event_queue.shift(@event_queue.length)
      return if events.empty?

      send_batch(events)
    end

    def shutdown
      @flush_thread&.kill if @auto_flush
      flush unless @event_queue.empty?
    end

    private

    def debug_event_data(events)
      return unless @debug

      puts "\n=== Event Data Debug Information ==="
      events.each_with_index do |event, index|
        puts "Event #{index + 1}:"
        puts "  ID: #{event[:id]}"
        puts "  Type: #{event[:type]}"
        puts "  Timestamp: #{event[:timestamp]}"
        puts "  Body keys: #{event[:body]&.keys || 'nil'}"

        # 检查常见的问题
        puts '  ⚠️  WARNING: Empty or nil type!' if event[:type].nil? || event[:type].to_s.empty?

        puts '  ⚠️  WARNING: Empty body!' if event[:body].nil?

        puts '  ---'
      end
      puts "=== End Debug Information ===\n"
    end

    def send_batch(events)
      # 调试事件数据
      debug_event_data(events)

      # 验证事件数据
      valid_events = events.select do |event|
        if event[:type].nil? || event[:type].to_s.empty?
          puts "Warning: Event with empty type detected, skipping: #{event[:id]}" if @debug
          false
        elsif event[:body].nil?
          puts "Warning: Event with empty body detected, skipping: #{event[:id]}" if @debug
          false
        else
          true
        end
      end

      if valid_events.empty?
        puts 'No valid events to send' if @debug
        return
      end

      batch_data = build_batch_data(valid_events)
      puts "Sending batch data: #{batch_data}" if @debug

      begin
        response = post('/api/public/ingestion', batch_data)
        puts "Flushed #{valid_events.length} events" if @debug
        response
      rescue StandardError => e
        puts "Failed to flush events: #{e.message}" if @debug
        # Re-queue events on failure
        valid_events.each { |event| @event_queue << event }
        raise
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
          sleep(@flush_interval) # Configurable flush interval
          begin
            flush unless @event_queue.empty?
          rescue StandardError => e
            puts "Error in flush thread: #{e.message}" if @debug
          end
        end
      end
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
      puts "Handling response with status: #{response.status}" if @debug

      case response.status
      when 200..299
        response
      when 401
        raise AuthenticationError, "Authentication failed: #{response.body}"
      when 404
        # 404 错误通常返回 HTML 页面
        error_message = 'Resource not found (404)'
        error_message += if response.body.is_a?(String) && response.body.include?('<!DOCTYPE html>')
                           '. Server returned HTML page instead of JSON API response. ' \
                             'This usually means the requested resource does not exist.'
                         else
                           ": #{response.body}"
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
              "Event type validation failed (#{response.status}): The event type or structure is " \
              "invalid. Please check the event format.#{error_details}"

      when 500..599
        raise APIError, "Server error (#{response.status}): #{response.body}"
      else
        raise APIError, "Unexpected response (#{response.status}): #{response.body}"
      end
    end
  end
end
