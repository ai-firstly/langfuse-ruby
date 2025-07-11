require 'securerandom'
require 'time'

module Langfuse
  module Utils
    class << self
      def generate_id
        SecureRandom.uuid
      end

      def current_timestamp
        Time.now.utc.iso8601(3)
      end

      def deep_symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = key.is_a?(String) ? key.to_sym : key
          new_value = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
          result[new_key] = new_value
        end
      end

      def deep_stringify_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = key.to_s
          new_value = value.is_a?(Hash) ? deep_stringify_keys(value) : value
          result[new_key] = new_value
        end
      end

      def validate_required_fields(data, required_fields)
        missing_fields = required_fields.select { |field| data[field].nil? || data[field].to_s.empty? }
        raise ValidationError, "Missing required fields: #{missing_fields.join(', ')}" unless missing_fields.empty?
      end
    end
  end
end
