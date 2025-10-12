# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::PromptTemplate do
  describe '.from_template' do
    it 'creates a prompt template from string' do
      template = described_class.from_template('Hello {{name}}!')

      expect(template).to be_a(described_class)
      expect(template.input_variables).to eq(['name'])
    end

    it 'extracts multiple variables' do
      template = described_class.from_template('Hello {{name}}! How are you feeling {{mood}} today?')

      expect(template.input_variables).to include('name', 'mood')
      expect(template.input_variables.length).to eq(2)
    end

    it 'handles repeated variables' do
      template = described_class.from_template('{{greeting}} {{name}}! {{greeting}} again, {{name}}!')

      expect(template.input_variables).to eq(['greeting', 'name'])
    end

    it 'handles no variables' do
      template = described_class.from_template('Hello world!')

      expect(template.input_variables).to be_empty
    end

    it 'handles complex variable patterns' do
      template = described_class.from_template('Process: {{action}} on {{object_type}} with id {{object_id}}')

      expect(template.input_variables).to eq(['action', 'object_type', 'object_id'])
    end

    it 'handles variables with underscores and numbers' do
      template = described_class.from_template('Config: {{var_name_1}} and {{var_2_name}}')

      expect(template.input_variables).to eq(['var_name_1', 'var_2_name'])
    end
  end

  describe '#format' do
    it 'formats template with provided values' do
      template = described_class.from_template('Hello {{name}}!')
      result = template.format(name: 'Alice')

      expect(result).to eq('Hello Alice!')
    end

    it 'formats template with multiple variables' do
      template = described_class.from_template('Hello {{name}}! How are you feeling {{mood}} today?')
      result = template.format(name: 'Alice', mood: 'happy')

      expect(result).to eq('Hello Alice! How are you feeling happy today?')
    end

    it 'raises error for missing variables' do
      template = described_class.from_template('Hello {{name}}!')

      expect { template.format({}) }.to raise_error(Langfuse::ValidationError, /Missing required variable/)
    end

    it 'replaces all occurrences of a variable' do
      template = described_class.from_template('{{greeting}} {{name}}! {{greeting}} again, {{name}}!')
      result = template.format(greeting: 'Hi', name: 'Bob')

      expect(result).to eq('Hi Bob! Hi again, Bob!')
    end

    it 'handles complex formatting scenarios' do
      template = described_class.from_template(
        'User: {{user_name}} (ID: {{user_id}})\n' \
        'Action: {{action}}\n' \
        'Target: {{target_type}} {{target_id}}\n' \
        'Timestamp: {{timestamp}}'
      )

      result = template.format(
        user_name: 'John Doe',
        user_id: '12345',
        action: 'delete',
        target_type: 'document',
        target_id: 'doc-789',
        timestamp: '2024-01-15T10:30:00Z'
      )

      expect(result).to include('User: John Doe (ID: 12345)')
      expect(result).to include('Action: delete')
      expect(result).to include('Target: document doc-789')
      expect(result).to include('Timestamp: 2024-01-15T10:30:00Z')
    end

    it 'handles empty values' do
      template = described_class.from_template('{{name}}: {{message}}')
      result = template.format(name: 'System', message: '')

      expect(result).to eq('System: ')
    end

    it 'handles nil values gracefully' do
      template = described_class.from_template('Value: {{data}}')
      result = template.format(data: nil)

      expect(result).to eq('Value: ')
    end
  end

  describe 'edge cases' do
    it 'handles malformed template syntax' do
      template = described_class.from_template('Hello {{name! How are you?')

      # Should not raise an error, but handle gracefully
      expect(template.input_variables).to be_empty
    end

    it 'handles nested braces' do
      template = described_class.from_template('Hello {{{name}}}!')

      # Should handle gracefully or extract outer variable
      expect(template.input_variables).to include('name')
    end

    it 'handles template with only variables' do
      template = described_class.from_template('{{var1}}{{var2}}{{var3}}')
      result = template.format(var1: 'A', var2: 'B', var3: 'C')

      expect(result).to eq('ABC')
    end

    it 'handles template with special characters' do
      template = described_class.from_template('Special: {{chars}}!@#$%^&*()')
      result = template.format(chars: 'ABC123')

      expect(result).to eq('Special: ABC123!@#$%^&*()')
    end
  end
end

RSpec.describe Langfuse::ChatPromptTemplate do
  describe '.from_messages' do
    it 'creates chat prompt from messages array' do
      messages = [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'Hello!' }
      ]

      template = described_class.from_messages(messages)

      expect(template).to be_a(described_class)
      expect(template.input_variables).to be_empty
    end

    it 'extracts variables from message content' do
      messages = [
        { role: 'system', content: 'You are a helpful {{role}} assistant.' },
        { role: 'user', content: '{{user_input}}' }
      ]

      template = described_class.from_messages(messages)

      expect(template.input_variables).to include('role', 'user_input')
    end

    it 'handles complex message structures' do
      messages = [
        { role: 'system', content: 'You are a {{domain}} expert specializing in {{topic}}.' },
        { role: 'user', content: 'Help me with {{task}} regarding {{subject}}.' },
        { role: 'assistant', content: 'I will help you with {{task}} about {{subject}} in {{domain}}.' }
      ]

      template = described_class.from_messages(messages)

      expect(template.input_variables).to include('domain', 'topic', 'task', 'subject')
    end

    it 'handles empty messages array' do
      template = described_class.from_messages([])

      expect(template.input_variables).to be_empty
    end

    it 'handles messages with no variables' do
      messages = [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'Hello!' },
        { role: 'assistant', content: 'Hi there!' }
      ]

      template = described_class.from_messages(messages)

      expect(template.input_variables).to be_empty
    end

    it 'handles messages with repeated variables' do
      messages = [
        { role: 'system', content: 'Your name is {{assistant_name}}.' },
        { role: 'user', content: 'Hello {{assistant_name}}!' },
        { role: 'assistant', content: 'Hi! I am {{assistant_name}}.' }
      ]

      template = described_class.from_messages(messages)

      expect(template.input_variables).to eq(['assistant_name'])
    end
  end

  describe '#format' do
    it 'formats chat messages with provided values' do
      messages = [
        { role: 'system', content: 'You are a helpful {{role}} assistant.' },
        { role: 'user', content: '{{user_input}}' }
      ]

      template = described_class.from_messages(messages)
      result = template.format(role: 'coding', user_input: 'Help me with Ruby')

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)

      expect(result[0][:role]).to eq('system')
      expect(result[0][:content]).to eq('You are a helpful coding assistant.')

      expect(result[1][:role]).to eq('user')
      expect(result[1][:content]).to eq('Help me with Ruby')
    end

    it 'formats complex conversation with multiple variables' do
      messages = [
        { role: 'system', content: 'You are a {{domain}} expert specializing in {{topic}}.' },
        { role: 'user', content: 'Help me with {{task}} regarding {{subject}}.' },
        { role: 'assistant', content: 'I will help you with {{task}} about {{subject}} in {{domain}}.' },
        { role: 'user', content: 'Great! My specific question is: {{question}}' }
      ]

      template = described_class.from_messages(messages)
      result = template.format(
        domain: 'physics',
        topic: 'quantum mechanics',
        task: 'understanding',
        subject: 'superposition',
        question: 'How can a particle be in multiple states at once?'
      )

      expect(result.length).to eq(4)
      expect(result[0][:content]).to include('physics expert')
      expect(result[1][:content]).to include('understanding regarding superposition')
      expect(result[2][:content]).to include('understanding about superposition in physics')
      expect(result[3][:content]).to include('How can a particle be in multiple states at once?')
    end

    it 'raises error for missing variables' do
      messages = [
        { role: 'system', content: 'You are a {{role}} assistant.' },
        { role: 'user', content: 'Hello!' }
      ]

      template = described_class.from_messages(messages)

      expect { template.format({}) }.to raise_error(Langfuse::ValidationError, /Missing required variable/)
    end

    it 'preserves message structure and roles' do
      messages = [
        { role: 'system', content: 'System message with {{var}}' },
        { role: 'user', content: 'User message' },
        { role: 'assistant', content: 'Assistant response with {{var}}' },
        { role: 'function_call', content: 'Function call' },
        { role: 'function_result', content: 'Function result' }
      ]

      template = described_class.from_messages(messages)
      result = template.format(var: 'value')

      expect(result.map { |msg| msg[:role] }).to eq(
        ['system', 'user', 'assistant', 'function_call', 'function_result']
      )
    end

    it 'handles additional message fields' do
      messages = [
        { role: 'system', content: 'System {{var}}', name: 'system_prompt' },
        { role: 'user', content: 'User {{var}}', name: 'user_input' }
      ]

      template = described_class.from_messages(messages)
      result = template.format(var: 'value')

      expect(result[0][:name]).to eq('system_prompt')
      expect(result[1][:name]).to eq('user_input')
      expect(result[0][:content]).to eq('System value')
      expect(result[1][:content]).to eq('User value')
    end
  end

  describe 'complex scenarios' do
    it 'handles few-shot prompting examples' do
      messages = [
        { role: 'system', content: 'You are a {{task}} assistant.' },
        { role: 'user', content: 'Example input: {{example_input_1}}' },
        { role: 'assistant', content: 'Example output: {{example_output_1}}' },
        { role: 'user', content: 'Example input: {{example_input_2}}' },
        { role: 'assistant', content: 'Example output: {{example_output_2}}' },
        { role: 'user', content: 'Now help with: {{actual_input}}' }
      ]

      template = described_class.from_messages(messages)
      result = template.format(
        task: 'classification',
        example_input_1: 'I love this product!',
        example_output_1: 'Positive sentiment',
        example_input_2: 'This is terrible.',
        example_output_2: 'Negative sentiment',
        actual_input: 'The product is okay, not great.'
      )

      expect(result.length).to eq(6)
      expect(result[0][:content]).to eq('You are a classification assistant.')
      expect(result[1][:content]).to eq('Example input: I love this product!')
      expect(result[2][:content]).to eq('Example output: Positive sentiment')
      expect(result[5][:content]).to eq('Now help with: The product is okay, not great.')
    end

    it 'handles code generation prompts' do
      messages = [
        { role: 'system', content: 'You are an expert {{language}} programmer.' },
        { role: 'user', content: 'Write a {{language}} function to {{task}} using {{framework}}.' },
        { role: 'assistant', content: 'Here is a {{language}} function using {{framework}}:\n\n```{{language}}\n{{code_placeholder}}\n```' }
      ]

      template = described_class.from_messages(messages)
      result = template.format(
        language: 'Python',
        task: 'create a REST API endpoint',
        framework: 'Flask',
        code_placeholder: '# Your code here'
      )

      expect(result[0][:content]).to eq('You are an expert Python programmer.')
      expect(result[1][:content]).to eq('Write a Python function to create a REST API endpoint using Flask.')
      expect(result[2][:content]).to include('Python function using Flask')
      expect(result[2][:content]).to include('```Python')
    end
  end
end