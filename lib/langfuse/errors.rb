module Langfuse
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class APIError < Error; end
  class NetworkError < Error; end
  class ValidationError < Error; end
  class RateLimitError < Error; end
  class TimeoutError < Error; end
end
