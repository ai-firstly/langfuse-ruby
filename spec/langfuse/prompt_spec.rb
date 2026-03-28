# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Prompt do
  let(:text_prompt_data) do
    {
      id: 'prompt-1',
      name: 'test-prompt',
      version: 1,
      prompt: 'Hello {{name}}, welcome to {place}!',
      config: { temperature: 0.7 },
      labels: ['production'],
      tags: ['greeting'],
      type: 'text',
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-02T00:00:00Z'
    }
  end

  let(:chat_prompt_data) do
    {
      id: 'prompt-2',
      name: 'chat-prompt',
      version: 2,
      prompt: [
        { role: 'system', content: 'You are a helpful assistant for {{company}}.' },
        { role: 'user', content: 'Tell me about {topic}.' }
      ],
      config: {},
      labels: [],
      tags: [],
      type: 'chat',
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-02T00:00:00Z'
    }
  end

  describe '#initialize' do
    it 'initializes with symbol keys' do
      prompt = described_class.new(text_prompt_data)

      expect(prompt.id).to eq('prompt-1')
      expect(prompt.name).to eq('test-prompt')
      expect(prompt.version).to eq(1)
      expect(prompt.prompt).to eq('Hello {{name}}, welcome to {place}!')
      expect(prompt.config).to eq({ temperature: 0.7 })
      expect(prompt.labels).to eq(['production'])
      expect(prompt.tags).to eq(['greeting'])
      expect(prompt.type).to eq('text')
      expect(prompt.created_at).to eq('2024-01-01T00:00:00Z')
      expect(prompt.updated_at).to eq('2024-01-02T00:00:00Z')
    end

    it 'initializes with string keys via deep_symbolize_keys' do
      data = {
        'id' => 'prompt-3',
        'name' => 'string-key-prompt',
        'version' => 1,
        'prompt' => 'Hello {{name}}!',
        'type' => 'text',
        'config' => { 'temperature' => 0.5 }
      }

      prompt = described_class.new(data)

      expect(prompt.id).to eq('prompt-3')
      expect(prompt.name).to eq('string-key-prompt')
      expect(prompt.config).to eq({ temperature: 0.5 })
      expect(prompt.type).to eq('text')
    end

    it 'defaults config to empty hash when not provided' do
      prompt = described_class.new({ id: 'p1', name: 'n', type: 'text', prompt: 'hi' })

      expect(prompt.config).to eq({})
    end

    it 'defaults labels and tags to empty arrays when not provided' do
      prompt = described_class.new({ id: 'p1', name: 'n', type: 'text', prompt: 'hi' })

      expect(prompt.labels).to eq([])
      expect(prompt.tags).to eq([])
    end
  end

  describe '#compile' do
    context 'with type text' do
      it 'substitutes {{var}} variables' do
        prompt = described_class.new(text_prompt_data)

        result = prompt.compile(name: 'Alice', place: 'Wonderland')

        expect(result).to eq('Hello Alice, welcome to Wonderland!')
      end

      it 'substitutes {var} variables' do
        data = text_prompt_data.merge(prompt: 'Hi {name}, you are in {place}.')
        prompt = described_class.new(data)

        result = prompt.compile(name: 'Bob', place: 'Paris')

        expect(result).to eq('Hi Bob, you are in Paris.')
      end

      it 'handles both {{var}} and {var} in the same template' do
        data = text_prompt_data.merge(prompt: '{{greeting}} {name}!')
        prompt = described_class.new(data)

        result = prompt.compile(greeting: 'Hey', name: 'Carol')

        expect(result).to eq('Hey Carol!')
      end

      it 'does not modify the original prompt' do
        prompt = described_class.new(text_prompt_data)

        prompt.compile(name: 'Alice', place: 'Wonderland')

        expect(prompt.prompt).to eq('Hello {{name}}, welcome to {place}!')
      end
    end

    context 'with type chat' do
      it 'substitutes variables in message contents' do
        prompt = described_class.new(chat_prompt_data)

        result = prompt.compile(company: 'Acme', topic: 'AI')

        expect(result).to eq([
          { role: 'system', content: 'You are a helpful assistant for Acme.' },
          { role: 'user', content: 'Tell me about AI.' }
        ])
      end

      it 'does not modify the original prompt messages' do
        prompt = described_class.new(chat_prompt_data)

        prompt.compile(company: 'Acme', topic: 'AI')

        expect(prompt.prompt[0][:content]).to eq('You are a helpful assistant for {{company}}.')
      end
    end

    context 'with unsupported type' do
      it 'raises ValidationError' do
        prompt = described_class.new(text_prompt_data.merge(type: 'unknown'))

        expect do
          prompt.compile(name: 'Alice')
        end.to raise_error(Langfuse::ValidationError, 'Unsupported prompt type: unknown')
      end
    end
  end

  describe '#get_langchain_prompt' do
    context 'with type text' do
      it 'returns a langchain-compatible prompt hash' do
        prompt = described_class.new(text_prompt_data)

        result = prompt.get_langchain_prompt

        expect(result[:_type]).to eq('prompt')
        expect(result[:template]).to eq('Hello {{name}}, welcome to {place}!')
        expect(result[:input_variables]).to contain_exactly('name', 'place')
      end
    end

    context 'with type chat' do
      it 'returns a langchain-compatible chat prompt hash' do
        prompt = described_class.new(chat_prompt_data)

        result = prompt.get_langchain_prompt

        expect(result[:_type]).to eq('chat')
        expect(result[:messages]).to be_an(Array)
        expect(result[:messages].length).to eq(2)
        expect(result[:messages][0][:_type]).to eq('system_message')
        expect(result[:messages][0][:content]).to eq('You are a helpful assistant for {{company}}.')
        expect(result[:messages][0][:input_variables]).to eq(['company'])
        expect(result[:messages][1][:_type]).to eq('user_message')
        expect(result[:messages][1][:input_variables]).to eq(['topic'])
        expect(result[:input_variables]).to contain_exactly('company', 'topic')
      end
    end

    context 'with unsupported type' do
      it 'raises ValidationError' do
        prompt = described_class.new(text_prompt_data.merge(type: 'invalid'))

        expect do
          prompt.get_langchain_prompt
        end.to raise_error(Langfuse::ValidationError, 'Unsupported prompt type: invalid')
      end
    end
  end

  describe '#to_dict' do
    it 'returns all fields as a hash' do
      prompt = described_class.new(text_prompt_data)

      result = prompt.to_dict

      expect(result).to eq({
        id: 'prompt-1',
        name: 'test-prompt',
        version: 1,
        prompt: 'Hello {{name}}, welcome to {place}!',
        config: { temperature: 0.7 },
        labels: ['production'],
        tags: ['greeting'],
        type: 'text',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-02T00:00:00Z'
      })
    end
  end
end

RSpec.describe Langfuse::PromptTemplate do
  describe '#initialize' do
    it 'initializes with template and input_variables' do
      template = described_class.new(template: 'Hello {{name}}!', input_variables: ['name'])

      expect(template.template).to eq('Hello {{name}}!')
      expect(template.input_variables).to eq(['name'])
    end

    it 'defaults input_variables to empty array' do
      template = described_class.new(template: 'Hello!')

      expect(template.input_variables).to eq([])
    end
  end

  describe '#format' do
    it 'substitutes {{var}} variables' do
      template = described_class.new(template: 'Hello {{name}}!', input_variables: ['name'])

      result = template.format(name: 'Alice')

      expect(result).to eq('Hello Alice!')
    end

    it 'substitutes {var} variables' do
      template = described_class.new(template: 'Hello {name}!', input_variables: ['name'])

      result = template.format(name: 'Bob')

      expect(result).to eq('Hello Bob!')
    end

    it 'substitutes both {{var}} and {var} in the same template' do
      template = described_class.new(
        template: '{{greeting}} {name}, welcome to {{place}}!',
        input_variables: %w[greeting name place]
      )

      result = template.format(greeting: 'Hi', name: 'Carol', place: 'Mars')

      expect(result).to eq('Hi Carol, welcome to Mars!')
    end

    it 'does not modify the original template' do
      template = described_class.new(template: 'Hello {{name}}!', input_variables: ['name'])

      template.format(name: 'Alice')

      expect(template.template).to eq('Hello {{name}}!')
    end
  end

  describe '.from_template' do
    it 'extracts {{var}} variables from template' do
      template = described_class.from_template('Hello {{name}}, you are {{age}} years old.')

      expect(template.template).to eq('Hello {{name}}, you are {{age}} years old.')
      expect(template.input_variables).to contain_exactly('name', 'age')
    end

    it 'extracts {var} variables from template' do
      template = described_class.from_template('Hello {name}, you are {age} years old.')

      expect(template.input_variables).to contain_exactly('name', 'age')
    end

    it 'deduplicates variables across {{var}} and {var} formats' do
      template = described_class.from_template('{{name}} is {name}.')

      expect(template.input_variables).to eq(['name'])
    end

    it 'returns empty variables for template with no variables' do
      template = described_class.from_template('Hello world!')

      expect(template.input_variables).to eq([])
    end
  end
end

RSpec.describe Langfuse::ChatPromptTemplate do
  let(:messages) do
    [
      { role: 'system', content: 'You are {{role}}.' },
      { role: 'user', content: 'Tell me about {topic}.' }
    ]
  end

  describe '#initialize' do
    it 'initializes with messages and input_variables' do
      template = described_class.new(messages: messages, input_variables: %w[role topic])

      expect(template.messages).to eq(messages)
      expect(template.input_variables).to eq(%w[role topic])
    end

    it 'defaults input_variables to empty array' do
      template = described_class.new(messages: [{ role: 'user', content: 'Hello!' }])

      expect(template.input_variables).to eq([])
    end
  end

  describe '#format' do
    it 'substitutes variables in message contents' do
      template = described_class.new(messages: messages, input_variables: %w[role topic])

      result = template.format(role: 'a teacher', topic: 'math')

      expect(result).to eq([
        { role: 'system', content: 'You are a teacher.' },
        { role: 'user', content: 'Tell me about math.' }
      ])
    end

    it 'does not modify the original messages' do
      template = described_class.new(messages: messages, input_variables: %w[role topic])

      template.format(role: 'a teacher', topic: 'math')

      expect(template.messages[0][:content]).to eq('You are {{role}}.')
    end
  end

  describe '.from_messages' do
    it 'extracts variables from all messages' do
      template = described_class.from_messages(messages)

      expect(template.messages).to eq(messages)
      expect(template.input_variables).to contain_exactly('role', 'topic')
    end

    it 'deduplicates variables across messages' do
      msgs = [
        { role: 'system', content: 'Context: {{topic}}' },
        { role: 'user', content: 'Tell me about {{topic}} and {detail}.' }
      ]

      template = described_class.from_messages(msgs)

      expect(template.input_variables).to contain_exactly('topic', 'detail')
    end

    it 'returns empty variables when messages have no variables' do
      msgs = [{ role: 'user', content: 'Hello!' }]

      template = described_class.from_messages(msgs)

      expect(template.input_variables).to eq([])
    end
  end
end
