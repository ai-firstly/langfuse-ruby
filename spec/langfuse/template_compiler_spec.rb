# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::TemplateCompiler do
  describe '.compile' do
    it 'substitutes both {{var}} and {var} placeholders' do
      result = described_class.compile('{{greeting}} {name}!', greeting: 'Hi', name: 'Alice')

      expect(result).to eq('Hi Alice!')
    end

    it 'accepts string keys and non-string values' do
      result = described_class.compile('{{name}} is {{age}}', 'name' => 'Bob', 'age' => 42)

      expect(result).to eq('Bob is 42')
    end

    it 'leaves placeholders without a matching variable untouched' do
      result = described_class.compile('{{known}} and {{unknown}}', known: 'yes')

      expect(result).to eq('yes and {{unknown}}')
    end

    it 'does not expand placeholders contained in a substituted value' do
      result = described_class.compile('{{user_input}} {{secret}}', user_input: '{{secret}}', secret: 'sk-123')

      expect(result).to eq('{{secret}} sk-123')
    end

    it 'prefers the longest variable name when names overlap' do
      result = described_class.compile('{{user_name}}', user: 'short', user_name: 'long')

      expect(result).to eq('long')
    end

    it 'supports variable names with non-word characters' do
      result = described_class.compile('{{user.name}}', 'user.name' => 'Ann')

      expect(result).to eq('Ann')
    end

    it 'returns the template unchanged when no variables are given' do
      expect(described_class.compile('Hello {{name}}!')).to eq('Hello {{name}}!')
    end

    it 'does not mutate the template' do
      template = 'Hello {{name}}!'

      described_class.compile(template, name: 'Alice')

      expect(template).to eq('Hello {{name}}!')
    end
  end

  describe '.compile_messages' do
    let(:messages) do
      [
        { role: 'system', content: 'You are {{role}}.' },
        { role: 'user', content: 'Tell me about {topic}.' }
      ]
    end

    it 'compiles each message content and keeps the role' do
      result = described_class.compile_messages(messages, role: 'a teacher', topic: 'math')

      expect(result).to eq([
                             { role: 'system', content: 'You are a teacher.' },
                             { role: 'user', content: 'Tell me about math.' }
                           ])
    end

    it 'does not mutate the original messages' do
      described_class.compile_messages(messages, role: 'a teacher', topic: 'math')

      expect(messages[0][:content]).to eq('You are {{role}}.')
    end

    it 'supports string-keyed message hashes and preserves extra keys' do
      string_messages = [
        { 'role' => 'user', 'content' => 'Hello {name}!', 'name' => 'Alice', 'tool_calls' => [] }
      ]
      result = described_class.compile_messages(string_messages, name: 'Bob')

      expect(result.first[:role]).to eq('user')
      expect(result.first[:content]).to eq('Hello Bob!')
      expect(result.first['tool_calls']).to eq([])
    end
  end

  describe '.extract_variables' do
    it 'extracts both placeholder formats and deduplicates' do
      expect(described_class.extract_variables('{{name}} is {name}, {place} too')).to eq(%w[name place])
    end

    it 'extracts variables with dot notation' do
      expect(described_class.extract_variables('{{user.name}} and {profile.email}')).to eq(%w[user.name profile.email])
    end

    it 'returns an empty array when there are no placeholders' do
      expect(described_class.extract_variables('Hello world!')).to eq([])
    end
  end

  describe '.extract_message_variables' do
    it 'collects variables across messages without duplicates' do
      messages = [
        { role: 'system', content: 'Context: {{topic}}' },
        { role: 'user', content: 'Tell me about {{topic}} and {detail}.' }
      ]

      expect(described_class.extract_message_variables(messages)).to contain_exactly('topic', 'detail')
    end

    it 'supports string-keyed messages in extract_message_variables' do
      messages = [
        { 'role' => 'user', 'content' => 'Tell me about {{user.query}}.' }
      ]

      expect(described_class.extract_message_variables(messages)).to eq(['user.query'])
    end
  end
end
