# frozen_string_literal: true

require_relative 'langfuse/version'
require_relative 'langfuse/observation_types'
require_relative 'langfuse/client'
require_relative 'langfuse/trace'
require_relative 'langfuse/span'
require_relative 'langfuse/generation'
require_relative 'langfuse/event'
require_relative 'langfuse/prompt'
require_relative 'langfuse/evaluation'
require_relative 'langfuse/errors'
require_relative 'langfuse/utils'
require_relative 'langfuse/null_objects'

# Ruby SDK for Langfuse - Open source LLM engineering platform
module Langfuse
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

    # Get a thread-safe singleton client instance
    # @return [Client] Langfuse client
    def client
      Thread.current[:langfuse_client] ||= Client.new
    end

    # Get a prompt and optionally compile it with variables
    # @param prompt_name [String] prompt name
    # @param variables [Hash] optional variables for compilation
    # @param label [String] optional prompt label (defaults to 'production' or 'latest')
    # @param version [Integer] optional prompt version
    # @param cache_ttl_seconds [Integer] cache TTL in seconds (default: 60)
    # @param retries [Integer] number of retries on failure (default: 2)
    # @return [String, Prompt, nil] compiled prompt string if variables provided, Prompt object otherwise, nil on failure
    def get_prompt(prompt_name, variables: nil, label: nil, version: nil, cache_ttl_seconds: 60, retries: 2)
      attempts = 0

      begin
        attempts += 1
        prompt = client.get_prompt(prompt_name, label: label, version: version, cache_ttl_seconds: cache_ttl_seconds)

        if variables
          prompt.compile(variables)
        else
          prompt
        end
      rescue StandardError => e
        if attempts <= retries
          sleep_time = 2**(attempts - 1) * 0.1 # Exponential backoff: 0.1s, 0.2s, 0.4s...
          warn "Langfuse prompt fetch failed (#{prompt_name}), retrying in #{sleep_time}s... (attempt #{attempts}/#{retries + 1})" if configuration.debug
          sleep(sleep_time)
          retry
        end

        warn "Langfuse prompt fetch failed (#{prompt_name}): #{e.message}" if configuration.debug
        nil
      end
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
              metadata: nil, tags: nil, version: nil, release: nil, **kwargs, &block)
      trace = client.trace(
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

      if block_given?
        begin
          result = yield(trace)
          result
        ensure
          flush
        end
      else
        trace
      end
    rescue StandardError => e
      warn "Langfuse trace creation failed: #{e.message}" if configuration.debug

      # If block given, execute with NullTrace to ensure code continues
      if block_given?
        null_trace = NullTrace.new
        yield(null_trace)
      else
        NullTrace.new
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
      Thread.current[:langfuse_client] = nil
    end
  end

  # Configuration class for Langfuse client settings
  class Configuration
    attr_accessor :public_key, :secret_key, :host, :debug, :timeout, :retries, :flush_interval, :auto_flush

    def initialize
      @public_key = nil
      @secret_key = nil
      @host = 'https://us.cloud.langfuse.com'
      @debug = false
      @timeout = 30
      @retries = 3
      @flush_interval = 5
      @auto_flush = true
    end
  end
end
