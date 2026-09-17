# frozen_string_literal: true

require_relative 'langfuse/version'
require_relative 'langfuse/observation_types'
require_relative 'langfuse/span_wrappers'
require_relative 'langfuse/partial_updates'
require_relative 'langfuse/template_compiler'
require_relative 'langfuse/client'
require_relative 'langfuse/trace'
require_relative 'langfuse/span'
require_relative 'langfuse/generation'
require_relative 'langfuse/event'
require_relative 'langfuse/prompt'
require_relative 'langfuse/prompt_cache'
require_relative 'langfuse/evaluation'
require_relative 'langfuse/errors'
require_relative 'langfuse/utils'
require_relative 'langfuse/null_objects'
require_relative 'langfuse/otel_exporter'

# Ruby SDK for Langfuse - Open source LLM engineering platform
module Langfuse
  CLIENT_MUTEX = Mutex.new

  class << self
    # Configure the Langfuse client with default settings
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Create a new Langfuse client instance
    def new(**kwargs)
      Client.new(**kwargs)
    end

    # Get a process-wide, thread-safe singleton client instance
    # @return [Client] Langfuse client
    def client
      @client || CLIENT_MUTEX.synchronize { @client ||= Client.new }
    end

    # Get a prompt and optionally compile it with variables
    # @param prompt_name [String] prompt name
    # @param variables [Hash] optional variables for compilation
    # @param label [String] optional prompt label (defaults to 'production' or 'latest')
    # @param version [Integer] optional prompt version
    # @param cache_ttl_seconds [Integer] cache TTL in seconds (default: 60)
    # @param retries [Integer] number of retries on failure (default: 2)
    # @return [String, Prompt, nil] compiled prompt string if variables provided, Prompt object otherwise, nil on failure
    # `retries` is applied inside the HTTP layer, which retries only transient
    # failures (timeout, network, 429, 5xx), honors Retry-After and backs off with
    # jitter. A missing prompt therefore fails immediately instead of being
    # requested three times.
    def get_prompt(prompt_name, variables: nil, label: nil, version: nil, cache_ttl_seconds: 60, retries: 2)
      prompt = client.get_prompt(
        prompt_name,
        label: label,
        version: version,
        cache_ttl_seconds: cache_ttl_seconds,
        retries: retries
      )

      variables ? prompt.compile(variables) : prompt
    rescue StandardError => e
      warn "Langfuse prompt fetch failed (#{prompt_name}): #{e.message}" if configuration.debug
      nil
    end

    # Create a trace and optionally execute a block with it
    # When a block is given, the trace is yielded and flush is called automatically after the block
    # If trace creation fails, a NullTrace is yielded to ensure the block still executes
    #
    # @param name [String] trace name
    # @param user_id [String] optional user identifier
    # @param session_id [String] optional session identifier
    # @param input [Object] optional input data
    # @param output [Object] optional output data
    # @param metadata [Hash] optional metadata
    # @param tags [Array] optional tags
    # @param version [String] optional version
    # @param release [String] optional release
    # @yield [Trace, NullTrace] trace object for recording observations
    # @return [Object] block return value if block given, trace otherwise
    #
    # @example Block-based usage with automatic flush
    #   Langfuse.trace("my-trace", user_id: "user-1") do |trace|
    #     generation = trace.generation(name: "openai", model: "gpt-4", input: messages)
    #     response = call_openai(...)
    #     generation.end(output: response, usage: response.usage)
    #     trace.update(output: response)
    #   end
    #
    # @example Direct usage without block
    #   trace = Langfuse.trace("my-trace")
    #   # ... work with trace
    #   Langfuse.flush
    #
    def trace(name = nil, user_id: nil, session_id: nil, input: nil, output: nil,
              metadata: nil, tags: nil, version: nil, release: nil, **kwargs)
      # Only trace creation degrades to a NullTrace. An exception raised by the
      # block must propagate: rescuing it here and yielding again would run the
      # caller's block a second time (duplicate LLM calls and billing).
      trace =
        begin
          client.trace(
            name: name,
            user_id: user_id,
            session_id: session_id,
            input: input,
            output: output,
            metadata: metadata,
            tags: tags,
            version: version,
            release: release,
            **kwargs
          )
        rescue StandardError => e
          warn "Langfuse trace creation failed: #{e.message}" if configuration.debug
          NullTrace.new
        end

      return trace unless block_given?

      begin
        yield(trace)
      ensure
        flush
      end
    end

    # Flush all pending events to Langfuse
    def flush
      client.flush
    rescue StandardError => e
      warn "Langfuse flush failed: #{e.message}" if configuration.debug
    end

    # Shutdown the singleton client
    def shutdown
      client.shutdown
    rescue StandardError => e
      warn "Langfuse shutdown failed: #{e.message}" if configuration.debug
    end

    # Reset the singleton client (mainly for testing)
    def reset!
      CLIENT_MUTEX.synchronize { @client = nil }
    end
  end

  # Configuration class for Langfuse client settings
  class Configuration
    attr_accessor :public_key, :secret_key, :host, :debug, :timeout, :retries, :flush_interval, :auto_flush,
                  :ingestion_mode, :environment, :sample_rate, :mask, :flush_at, :max_queue_size, :logger,
                  :shutdown_on_exit, :http_adapter

    def initialize
      @public_key = nil
      @secret_key = nil
      @host = 'https://us.cloud.langfuse.com'
      @debug = false
      @timeout = 30
      @retries = 3
      @flush_interval = 5
      @auto_flush = true
      @ingestion_mode = :legacy # :legacy or :otel
      @environment = nil       # default tracing environment for all events
      @sample_rate = nil       # 0.0..1.0, nil disables sampling
      @mask = nil              # callable applied to input/output/metadata before sending
      @flush_at = 15           # flush as soon as this many events are queued
      @max_queue_size = 10_000 # queue cap; the oldest events are dropped when full
      @logger = nil            # custom Logger instance
      @shutdown_on_exit = true # register an at_exit hook that flushes pending events
      @http_adapter = nil      # Faraday adapter, e.g. :net_http_persistent for keep-alive
    end
  end
end
