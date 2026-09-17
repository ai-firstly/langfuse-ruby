# frozen_string_literal: true

module Langfuse
  class Prompt
    attr_reader :id, :name, :version, :prompt, :config, :labels, :tags, :type, :created_at, :updated_at

    def initialize(data)
      @data = data.is_a?(Hash) ? Utils.deep_symbolize_keys(data) : data

      @id = @data[:id]
      @name = @data[:name]
      @version = @data[:version]
      @prompt = @data[:prompt]
      @config = @data[:config] || {}
      @labels = @data[:labels] || []
      @tags = @data[:tags] || []
      @type = @data[:type]
      @created_at = @data[:created_at]
      @updated_at = @data[:updated_at]
    end

    def get_langchain_prompt
      # Convert Langfuse prompt format to LangChain format
      case @type
      when 'text'
        text_to_langchain_prompt
      when 'chat'
        chat_to_langchain_prompt
      else
        raise ValidationError, "Unsupported prompt type: #{@type}"
      end
    end

    def compile(variables = {})
      # Compile prompt with variables
      case @type
      when 'text'
        compile_text_prompt(variables)
      when 'chat'
        compile_chat_prompt(variables)
      else
        raise ValidationError, "Unsupported prompt type: #{@type}"
      end
    end

    def to_dict
      {
        id: @id,
        name: @name,
        version: @version,
        prompt: @prompt,
        config: @config,
        labels: @labels,
        tags: @tags,
        type: @type,
        created_at: @created_at,
        updated_at: @updated_at
      }
    end

    private

    def text_to_langchain_prompt
      # Convert text prompt to LangChain PromptTemplate format
      {
        _type: 'prompt',
        input_variables: TemplateCompiler.extract_variables(@prompt),
        template: @prompt
      }
    end

    def chat_to_langchain_prompt
      # Convert chat prompt to LangChain ChatPromptTemplate format
      messages = @prompt.map do |message|
        {
          _type: "#{message[:role]}_message",
          content: message[:content],
          input_variables: TemplateCompiler.extract_variables(message[:content])
        }
      end

      {
        _type: 'chat',
        messages: messages,
        input_variables: messages.flat_map { |m| m[:input_variables] }.uniq
      }
    end

    def compile_text_prompt(variables)
      TemplateCompiler.compile(@prompt, variables)
    end

    def compile_chat_prompt(variables)
      TemplateCompiler.compile_messages(@prompt, variables)
    end
  end

  class PromptTemplate
    attr_reader :template, :input_variables

    def initialize(template:, input_variables: [])
      @template = template
      @input_variables = input_variables
    end

    def format(variables = {})
      TemplateCompiler.compile(@template, variables)
    end

    def self.from_template(template)
      new(template: template, input_variables: extract_variables(template))
    end

    def self.extract_variables(text)
      TemplateCompiler.extract_variables(text)
    end
  end

  class ChatPromptTemplate
    attr_reader :messages, :input_variables

    def initialize(messages:, input_variables: [])
      @messages = messages
      @input_variables = input_variables
    end

    def format(variables = {})
      TemplateCompiler.compile_messages(@messages, variables)
    end

    def self.from_messages(messages)
      new(messages: messages, input_variables: TemplateCompiler.extract_message_variables(messages))
    end
  end
end
