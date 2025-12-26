require 'securerandom'
require 'time'
require 'erb'

module Langfuse
  module Utils
    class << self
      def generate_id
        SecureRandom.uuid
      end

      def current_timestamp
        Time.now.utc.iso8601(3)
      end

      def url_encode(string)
        ERB::Util.url_encode(string.to_s)
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
          new_key = camelize_key(key.to_s)
          new_value = value.is_a?(Hash) ? deep_stringify_keys(value) : value
          result[new_key] = new_value
        end
      end

      # 将哈希的键名转换为小驼峰格式
      def deep_camelize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = camelize_key(key.to_s)
          new_value = value.is_a?(Hash) ? deep_camelize_keys(value) : value
          result[new_key] = new_value
        end
      end

      private

      # 将蛇形命名转换为小驼峰命名
      def camelize_key(key)
        return key if key.empty? || !key.include?('_')

        key.split('_').map.with_index do |part, index|
          index.zero? ? part.downcase : part.capitalize
        end.join
      end

      def validate_required_fields(data, required_fields)
        missing_fields = required_fields.select { |field| data[field].nil? || data[field].to_s.empty? }
        raise ValidationError, "Missing required fields: #{missing_fields.join(', ')}" unless missing_fields.empty?
      end
    end
  end
end
