# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::AuthenticationError do
  describe 'error handling' do
    it 'creates an authentication error with message' do
      error = described_class.new('Invalid credentials')
      expect(error.message).to eq('Invalid credentials')
      expect(error).to be_a(StandardError)
    end

    it 'creates an authentication error with default message' do
      error = described_class.new
      expect(error.message).to eq('Authentication failed')
    end

    it 'inherits from Langfuse::Error' do
      error = described_class.new
      expect(error).to be_a(Langfuse::Error)
      expect(error).to be_a(StandardError)
    end

    it 'can be caught in rescue block' do
      expect do
        raise described_class, 'Test error'
      end.to raise_error(described_class, 'Test error')
    end
  end
end

RSpec.describe Langfuse::ValidationError do
  describe 'error handling' do
    it 'creates a validation error with message' do
      error = described_class.new('Invalid input data')
      expect(error.message).to eq('Invalid input data')
      expect(error).to be_a(StandardError)
    end

    it 'creates a validation error with default message' do
      error = described_class.new
      expect(error.message).to eq('Validation failed')
    end

    it 'inherits from Langfuse::Error' do
      error = described_class.new
      expect(error).to be_a(Langfuse::Error)
      expect(error).to be_a(StandardError)
    end

    it 'can be caught in rescue block' do
      expect do
        raise described_class, 'Validation failed: missing field'
      end.to raise_error(described_class, 'Validation failed: missing field')
    end
  end
end

RSpec.describe Langfuse::RateLimitError do
  describe 'error handling' do
    it 'creates a rate limit error with message' do
      error = described_class.new('Rate limit exceeded')
      expect(error.message).to eq('Rate limit exceeded')
      expect(error).to be_a(Langfuse::Error)
    end

    it 'inherits from Langfuse::Error' do
      error = described_class.new
      expect(error).to be_a(Langfuse::Error)
      expect(error).to be_a(StandardError)
    end

    it 'can be caught in rescue block' do
      expect do
        raise described_class, 'Too many requests'
      end.to raise_error(described_class, 'Too many requests')
    end
  end
end

RSpec.describe Langfuse::TimeoutError do
  describe 'error handling' do
    it 'creates a timeout error with message' do
      error = described_class.new('Request timeout')
      expect(error.message).to eq('Request timeout')
      expect(error).to be_a(Langfuse::Error)
    end

    it 'inherits from Langfuse::Error' do
      error = described_class.new
      expect(error).to be_a(Langfuse::Error)
      expect(error).to be_a(StandardError)
    end

    it 'can be caught in rescue block' do
      expect do
        raise described_class, 'Connection timed out'
      end.to raise_error(described_class, 'Connection timed out')
    end
  end
end

RSpec.describe Langfuse::NetworkError do
  describe 'error handling' do
    it 'creates a network error with message' do
      error = described_class.new('Connection timeout')
      expect(error.message).to eq('Connection timeout')
      expect(error).to be_a(StandardError)
    end

    it 'creates a network error with default message' do
      error = described_class.new
      expect(error.message).to eq('Network error')
    end

    it 'inherits from Langfuse::Error' do
      error = described_class.new
      expect(error).to be_a(Langfuse::Error)
      expect(error).to be_a(StandardError)
    end

    it 'can be caught in rescue block' do
      expect do
        raise described_class, 'Failed to connect to server'
      end.to raise_error(described_class, 'Failed to connect to server')
    end
  end
end

RSpec.describe Langfuse::APIError do
  describe 'error handling' do
    it 'creates an API error with message' do
      error = described_class.new('API rate limit exceeded')
      expect(error.message).to eq('API rate limit exceeded')
      expect(error).to be_a(StandardError)
    end

    it 'creates an API error with default message' do
      error = described_class.new
      expect(error.message).to eq('API error')
    end

    it 'inherits from Langfuse::Error' do
      error = described_class.new
      expect(error).to be_a(Langfuse::Error)
      expect(error).to be_a(StandardError)
    end

    it 'can be caught in rescue block' do
      expect do
        raise described_class, 'Invalid API response'
      end.to raise_error(described_class, 'Invalid API response')
    end
  end
end

RSpec.describe 'Error hierarchy and usage' do
  let(:client) { Langfuse::Client }

  describe 'client authentication errors' do
    it 'raises AuthenticationError for missing public key' do
      expect do
        client.new(secret_key: 'test_secret')
      end.to raise_error(Langfuse::AuthenticationError, /Public key is required/)
    end

    it 'raises AuthenticationError for missing secret key' do
      expect do
        client.new(public_key: 'test_public')
      end.to raise_error(Langfuse::AuthenticationError, /Secret key is required/)
    end

    it 'raises AuthenticationError for nil credentials' do
      expect do
        client.new(public_key: nil, secret_key: nil)
      end.to raise_error(Langfuse::AuthenticationError)
    end

    it 'raises AuthenticationError for empty string credentials' do
      expect do
        client.new(public_key: '', secret_key: '')
      end.to raise_error(Langfuse::AuthenticationError)
    end
  end

  describe 'error rescue patterns' do
    it 'can rescue specific error types' do
      result = nil

      begin
        raise Langfuse::ValidationError, 'Invalid prompt template'
      rescue Langfuse::ValidationError => e
        result = "Caught validation error: #{e.message}"
      end

      expect(result).to eq('Caught validation error: Invalid prompt template')
    end

    it 'can rescue multiple error types' do
      result = nil

      begin
        raise Langfuse::NetworkError, 'Connection failed'
      rescue Langfuse::AuthenticationError, Langfuse::NetworkError => e
        result = "Caught network/auth error: #{e.class.name}"
      end

      expect(result).to eq('Caught network/auth error: Langfuse::NetworkError')
    end

    it 'can rescue all Langfuse errors' do
      result = nil

      begin
        raise Langfuse::APIError, 'Server error'
      rescue Langfuse::AuthenticationError,
             Langfuse::ValidationError,
             Langfuse::RateLimitError,
             Langfuse::TimeoutError,
             Langfuse::NetworkError,
             Langfuse::APIError => e
        result = "Caught Langfuse error: #{e.class.name}"
      end

      expect(result).to eq('Caught Langfuse error: Langfuse::APIError')
    end
  end

  describe 'error inheritance chain' do
    it 'all custom errors inherit from Langfuse::Error' do
      errors = [
        Langfuse::AuthenticationError,
        Langfuse::ValidationError,
        Langfuse::RateLimitError,
        Langfuse::TimeoutError,
        Langfuse::NetworkError,
        Langfuse::APIError
      ]

      errors.each do |error_class|
        expect(error_class.superclass).to eq(Langfuse::Error)
      end
    end

    it 'Langfuse::Error inherits from StandardError' do
      expect(Langfuse::Error.superclass).to eq(StandardError)
    end
  end

  describe 'error with context' do
    it 'can include additional context in error messages' do
      error = Langfuse::ValidationError.new("Invalid field 'name': cannot be empty")
      expect(error.message).to include("Invalid field 'name'")
      expect(error.message).to include("cannot be empty")
    end

    it 'can provide detailed error information' do
      error = Langfuse::APIError.new("HTTP 429: Rate limit exceeded. Try again in 60 seconds.")
      expect(error.message).to include("HTTP 429")
      expect(error.message).to include("Rate limit")
    end
  end
end