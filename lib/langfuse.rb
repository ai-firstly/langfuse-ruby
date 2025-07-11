require_relative "langfuse/version"
require_relative "langfuse/client"
require_relative "langfuse/trace"
require_relative "langfuse/span"
require_relative "langfuse/generation"
require_relative "langfuse/prompt"
require_relative "langfuse/evaluation"
require_relative "langfuse/errors"
require_relative "langfuse/utils"

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

  class Configuration
    attr_accessor :public_key, :secret_key, :host, :debug, :timeout, :retries

    def initialize
      @public_key = nil
      @secret_key = nil
      @host = "https://cloud.langfuse.com"
      @debug = false
      @timeout = 30
      @retries = 3
    end
  end
end
