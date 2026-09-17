# frozen_string_literal: true

require 'securerandom'
require 'time'
require 'erb'

module Langfuse
  module Utils
    # Body keys whose values must be passed through verbatim (user data),
    # everything else nested under them keeps its original key format.
    VERBATIM_BODY_KEYS = %w[input output metadata usageDetails costDetails modelParameters].freeze

    class << self
      def generate_id
        SecureRandom.uuid
      end

      # W3C-compatible 32-char hex trace ID (16 bytes), used for OTel ingestion
      def generate_hex_trace_id
        SecureRandom.hex(16)
      end

      # W3C-compatible 16-char hex span/observation ID (8 bytes), used for OTel ingestion
      def generate_hex_span_id
        SecureRandom.hex(8)
      end

      def current_timestamp
        Time.now.utc.iso8601(3)
      end

      def url_encode(string)
        ERB::Util.url_encode(string.to_s)
      end

      def deep_symbolize_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            new_key = key.is_a?(String) ? key.to_sym : key
            result[new_key] = deep_symbolize_keys(value)
          end
        when Array
          object.map { |item| deep_symbolize_keys(item) }
        else
          object
        end
      end

      # 将哈希的键名转换为小驼峰格式
      def deep_camelize_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            new_key = camelize_key(key.to_s)
            result[new_key] = deep_camelize_keys(value)
          end
        when Array
          object.map { |item| deep_camelize_keys(item) }
        else
          object
        end
      end

      # Kept for backwards compatibility: it has always camelized keys rather
      # than only stringifying them.
      alias deep_stringify_keys deep_camelize_keys

      # Prepare an event body for the ingestion API:
      # - top-level keys are camelized (snake_case -> camelCase)
      # - user data values (input/output/metadata/usageDetails/costDetails/modelParameters)
      #   are passed through verbatim so user-provided keys are not mangled
      # - the legacy `usage` object keys are camelized (prompt_tokens -> promptTokens)
      def prepare_event_body(body)
        return body unless body.is_a?(Hash)

        body.each_with_object({}) do |(key, value), result|
          new_key = camelize_key(key.to_s)
          result[new_key] = if !VERBATIM_BODY_KEYS.include?(new_key) && value.is_a?(Hash)
                              deep_camelize_keys(value)
                            else
                              value
                            end
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
