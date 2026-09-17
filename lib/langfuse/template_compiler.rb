# frozen_string_literal: true

module Langfuse
  # Placeholder handling shared by Prompt, PromptTemplate and ChatPromptTemplate.
  # Both `{{var}}` and `{var}` are supported.
  module TemplateCompiler
    VARIABLE_PATTERN = /\{\{([a-zA-Z0-9_.]+)\}\}|\{([a-zA-Z0-9_.]+)\}/

    class << self
      # Substitutes every provided variable in a single pass, so a value that
      # itself contains a placeholder is never expanded again (a value like
      # "{{admin_prompt}}" stays literal). Placeholders without a matching
      # variable are left untouched.
      def compile(template, variables = {})
        text = template.to_s
        return text if variables.nil? || variables.empty?

        values = variables.to_h { |key, value| [key.to_s, value.to_s] }

        text.gsub(placeholder_pattern(values.keys)) do
          values[Regexp.last_match(1) || Regexp.last_match(2)]
        end
      end

      def compile_messages(messages, variables = {})
        messages.map do |message|
          role = message[:role] || message['role']
          content = compile(message[:content] || message['content'], variables)
          message.merge(role: role, content: content)
        end
      end

      def extract_variables(text)
        text.to_s.scan(VARIABLE_PATTERN).map { |double, single| double || single }.uniq
      end

      def extract_message_variables(messages)
        messages.flat_map do |message|
          content = message[:content] || message['content']
          extract_variables(content)
        end.uniq
      end

      private

      # Longest name first so a `user` variable cannot shadow `{{user_name}}`.
      def placeholder_pattern(names)
        alternatives = names.sort_by { |name| -name.length }
                            .map { |name| Regexp.escape(name) }
                            .join('|')

        /\{\{(#{alternatives})\}\}|\{(#{alternatives})\}/
      end
    end
  end
end
