require 'faraday'
require 'faraday/net_http'
require 'json'
require 'base64'
require 'concurrent'

module Langfuse
  class Client
    attr_reader :public_key, :secret_key, :host, :debug, :timeout, :retries

    def initialize(public_key: nil, secret_key: nil, host: nil, debug: false, timeout: 30, retries: 3)
      @public_key = public_key || ENV['LANGFUSE_PUBLIC_KEY'] || Langfuse.configuration.public_key
      @secret_key = secret_key || ENV['LANGFUSE_SECRET_KEY'] || Langfuse.configuration.secret_key
      @host = host || ENV['LANGFUSE_HOST'] || Langfuse.configuration.host
      @debug = debug || Langfuse.configuration.debug
      @timeout = timeout || Langfuse.configuration.timeout
      @retries = retries || Langfuse.configuration.retries

      raise AuthenticationError, 'Public key is required' unless @public_key
      raise AuthenticationError, 'Secret key is required' unless @secret_key

      @connection = build_connection
      @event_queue = Concurrent::Array.new
      @flush_thread = start_flush_thread
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
             version: nil, **kwargs)
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

    # Prompt operations
    def get_prompt(name, version: nil, label: nil, cache_ttl_seconds: 60)
      cache_key = "prompt:#{name}:#{version}:#{label}"

      if (cached_prompt = @prompt_cache&.dig(cache_key)) && (Time.now - cached_prompt[:cached_at] < cache_ttl_seconds)
        return cached_prompt[:prompt]
      end

      path = "/api/public/v2/prompts/#{name}"
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
    def score(name:, value:, trace_id: nil, observation_id: nil, data_type: nil, comment: nil, **kwargs)
      data = {
        name: name,
        value: value,
        data_type: data_type,
        comment: comment,
        **kwargs
      }

      data[:trace_id] = trace_id if trace_id
      data[:observation_id] = observation_id if observation_id

      enqueue_event('score-create', data)
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

    # Event queue management
    def enqueue_event(type, body)
      event = {
        id: Utils.generate_id,
        type: type,
        timestamp: Utils.current_timestamp,
        body: Utils.deep_stringify_keys(body)
      }

      @event_queue << event
      puts "Enqueued event: #{type}" if @debug
    end

    def flush
      return if @event_queue.empty?

      events = @event_queue.shift(@event_queue.length)
      return if events.empty?

      batch_data = {
        batch: events,
        metadata: {
          batch_size: events.length,
          sdk_name: 'langfuse-ruby',
          sdk_version: Langfuse::VERSION
        }
      }

      begin
        response = post('/api/public/ingestion', batch_data)
        puts "Flushed #{events.length} events" if @debug
      rescue StandardError => e
        puts "Failed to flush events: #{e.message}" if @debug
        # Re-queue events on failure
        events.each { |event| @event_queue << event }
        raise
      end
    end

    def shutdown
      @flush_thread&.kill
      flush unless @event_queue.empty?
    end

    private

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
        if retries_left > 0
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
        if response.body.is_a?(String) && response.body.include?('<!DOCTYPE html>')
          error_message += '. Server returned HTML page instead of JSON API response. This usually means the requested resource does not exist.'
        else
          error_message += ": #{response.body}"
        end
        raise ValidationError, error_message
      when 429
        raise RateLimitError, "Rate limit exceeded: #{response.body}"
      when 400..499
        raise ValidationError, "Client error (#{response.status}): #{response.body}"
      when 500..599
        raise APIError, "Server error (#{response.status}): #{response.body}"
      else
        raise APIError, "Unexpected response (#{response.status}): #{response.body}"
      end
    end

    def start_flush_thread
      Thread.new do
        loop do
          sleep(5) # Flush every 5 seconds
          begin
            flush unless @event_queue.empty?
          rescue StandardError => e
            puts "Error in flush thread: #{e.message}" if @debug
          end
        end
      end
    end
  end
end
