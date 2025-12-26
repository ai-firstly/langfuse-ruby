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
    def new(**options)
      Client.new(**options)
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
