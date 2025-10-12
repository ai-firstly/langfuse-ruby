# frozen_string_literal: true

module Langfuse
  class Error < StandardError; end

  class AuthenticationError < Error
    def initialize(message = 'Authentication failed')
      super(message)
    end
  end

  class APIError < Error
    def initialize(message = 'API error')
      super(message)
    end
  end

  class NetworkError < Error
    def initialize(message = 'Network error')
      super(message)
    end
  end

  class ValidationError < Error
    def initialize(message = 'Validation failed')
      super(message)
    end
  end

  class RateLimitError < Error; end
  class TimeoutError < Error; end
end
