# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Evaluators::ExactMatchEvaluator do
  let(:evaluator) { described_class.new }

  describe '#evaluate' do
    context 'when values match exactly' do
      it 'returns true for identical strings' do
        result = evaluator.evaluate(
          'What is 2+2?',
          '4',
          expected: '4'
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns true for identical numbers' do
        result = evaluator.evaluate(
          'Calculate 10 * 5',
          50,
          expected: 50
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns true for identical arrays' do
        result = evaluator.evaluate(
          'List colors',
          %w[red green blue],
          expected: %w[red green blue]
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns true for identical hashes' do
        result = evaluator.evaluate(
          'Return user data',
          { name: 'John', age: 30 },
          expected: { name: 'John', age: 30 }
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'is case sensitive for strings' do
        result = evaluator.evaluate(
          'Test case',
          'Hello',
          expected: 'hello'
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'considers whitespace differences' do
        result = evaluator.evaluate(
          'Test whitespace',
          'Hello World',
          expected: 'Hello  World'
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end
    end

    context 'when values do not match' do
      it 'returns false for different strings' do
        result = evaluator.evaluate(
          'What is the capital of France?',
          'London',
          expected: 'Paris'
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns false for different numbers' do
        result = evaluator.evaluate(
          'Calculate 10 + 5',
          14,
          expected: 15
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns false for different array lengths' do
        result = evaluator.evaluate(
          'List prime numbers',
          [2, 3, 5],
          expected: [2, 3, 5, 7]
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns false for different array elements' do
        result = evaluator.evaluate(
          'List colors',
          %w[red green blue],
          expected: %w[red yellow blue]
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end
    end

    context 'with nil values' do
      it 'handles nil output' do
        result = evaluator.evaluate(
          'Test',
          nil,
          expected: 'expected value'
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'handles nil expected' do
        result = evaluator.evaluate(
          'Test',
          'actual value',
          expected: nil
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns true when both are nil' do
        result = evaluator.evaluate(
          'Test',
          nil,
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end
    end
  end
end

RSpec.describe Langfuse::Evaluators::SimilarityEvaluator do
  let(:evaluator) { described_class.new }

  describe '#evaluate' do
    it 'returns numeric similarity score' do
      result = evaluator.evaluate(
        'What is AI?',
        'Artificial Intelligence',
        expected: 'AI is artificial intelligence'
      )

      expect(result).to be_a(Float)
      expect(result).to be_between(0, 1)
    end

    it 'returns higher score for similar content' do
      similar_result = evaluator.evaluate(
        'Test',
        'machine learning',
        expected: 'artificial intelligence and machine learning'
      )

      different_result = evaluator.evaluate(
        'Test',
        'cooking recipes',
        expected: 'artificial intelligence and machine learning'
      )

      expect(similar_result).to be > different_result
    end

    it 'returns 1 for identical strings' do
      result = evaluator.evaluate(
        'Test',
        'identical text',
        expected: 'identical text'
      )

      expect(result).to eq(1.0)
    end

    it 'handles empty strings' do
      result = evaluator.evaluate(
        'Test',
        '',
        expected: 'non-empty text'
      )

      expect(result).to be_a(Float)
      expect(result).to be >= 0
    end

    it 'handles special characters and punctuation' do
      result = evaluator.evaluate(
        'Test punctuation',
        'Hello, world!',
        expected: 'Hello world!'
      )

      expect(result).to be_a(Float)
      expect(result).to be > 0.8  # Should be very similar
    end
  end
end

RSpec.describe Langfuse::Evaluators::LengthEvaluator do
  describe '#evaluate' do
    context 'with min and max constraints' do
      let(:evaluator) { described_class.new(min_length: 5, max_length: 20) }

      it 'returns true for text within range' do
        result = evaluator.evaluate(
          'Test input',
          'This is good length',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns false for text shorter than min_length' do
        result = evaluator.evaluate(
          'Test input',
          'Too',
          expected: nil
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns false for text longer than max_length' do
        result = evaluator.evaluate(
          'Test input',
          'This text is definitely too long to pass the validation check',
          expected: nil
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns true for text exactly at boundaries' do
        exact_min_result = evaluator.evaluate(
          'Test',
          'Exact',
          expected: nil
        )

        exact_max_result = evaluator.evaluate(
          'Test',
          'This is twenty char!',
          expected: nil
        )

        expect(exact_min_result[:value]).to eq(1)
        expect(exact_max_result[:value]).to eq(1)
      end
    end

    context 'with only min_length' do
      let(:evaluator) { described_class.new(min_length: 10) }

      it 'returns true for text longer than min_length' do
        result = evaluator.evaluate(
          'Test',
          'This is long enough',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns false for text shorter than min_length' do
        result = evaluator.evaluate(
          'Test',
          'Short',
          expected: nil
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns true for very long text (no max limit)' do
        result = evaluator.evaluate(
          'Test',
          'This is a very long text that would normally exceed any reasonable maximum length but should pass since we only have a minimum constraint',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end
    end

    context 'with only max_length' do
      let(:evaluator) { described_class.new(max_length: 50) }

      it 'returns true for text shorter than max_length' do
        result = evaluator.evaluate(
          'Test',
          'This is short',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns false for text longer than max_length' do
        result = evaluator.evaluate(
          'Test',
          'This text is way too long and exceeds the maximum length constraint we have set',
          expected: nil
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'returns true for empty text (no min limit)' do
        result = evaluator.evaluate(
          'Test',
          '',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end
    end

    context 'without constraints' do
      let(:evaluator) { described_class.new }

      it 'returns true for any text length' do
        short_result = evaluator.evaluate('Test', 'Short', expected: nil)
        long_result = evaluator.evaluate('Test', 'This is a very long text', expected: nil)

        expect(short_result[:value]).to eq(1)
        expect(long_result[:value]).to eq(1)
      end
    end

    it 'handles non-string inputs' do
      evaluator = described_class.new(min_length: 1, max_length: 10)

      number_result = evaluator.evaluate('Test', 12345, expected: nil)
      array_result = evaluator.evaluate('Test', [1, 2, 3], expected: nil)

      expect(number_result[:value]).to eq(1)  # "12345" length is 5
      expect(array_result[:value]).to eq(1)   # "[1, 2, 3]" length is 9
    end
  end
end

RSpec.describe Langfuse::Evaluators::ContainsEvaluator do
  let(:evaluator) { described_class.new }

  describe '#evaluate' do
    it 'returns true when output contains expected substring' do
      result = evaluator.evaluate(
        'Find Ruby',
        'Ruby programming language',
        expected: 'Ruby'
      )

      expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
    end

    it 'returns false when output does not contain expected substring' do
      result = evaluator.evaluate(
        'Find Python',
        'JavaScript programming language',
        expected: 'Python'
      )

      expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
    end

    it 'is case sensitive by default' do
      result = evaluator.evaluate(
        'Test case',
        'ruby programming',
        expected: 'Ruby'
      )

      expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
    end

    it 'returns true for multiple occurrences' do
      result = evaluator.evaluate(
        'Test multiple',
        'Ruby is great. Ruby is dynamic. Ruby is fun.',
        expected: 'Ruby'
      )

      expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
    end

    it 'handles empty expected string' do
      result = evaluator.evaluate(
        'Test empty',
        'Any text',
        expected: ''
      )

      expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
    end

    it 'handles special characters in expected string' do
      result = evaluator.evaluate(
        'Test special chars',
        'Price: $99.99! Discount applied.',
        expected: '$99.99!'
      )

      expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
    end

    it 'handles whitespace in expected string' do
      result = evaluator.evaluate(
        'Test whitespace',
        'Hello   world!',
        expected: '   '
      )

      expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
    end

    it 'returns false for empty output with non-empty expected' do
      result = evaluator.evaluate(
        'Test empty output',
        '',
        expected: 'something'
      )

      expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
    end
  end
end

RSpec.describe Langfuse::Evaluators::RegexEvaluator do
  describe '#evaluate' do
    context 'with string pattern' do
      let(:evaluator) { described_class.new(pattern: '\d+') }

      it 'returns true when output matches pattern' do
        result = evaluator.evaluate(
          'Find numbers',
          'There are 42 apples',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns false when output does not match pattern' do
        result = evaluator.evaluate(
          'Find numbers',
          'There are no apples',
          expected: nil
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'handles complex patterns' do
        email_evaluator = described_class.new(pattern: '\A[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\z')

        valid_result = email_evaluator.evaluate(
          'Validate email',
          'user@example.com',
          expected: nil
        )

        invalid_result = email_evaluator.evaluate(
          'Validate email',
          'invalid-email',
          expected: nil
        )

        expect(valid_result[:value]).to eq(1)
        expect(invalid_result[:value]).to eq(0)
      end
    end

    context 'with Regexp object' do
      let(:evaluator) { described_class.new(pattern: /^[A-Z][a-z]+$/) }

      it 'returns true when output matches regex' do
        result = evaluator.evaluate(
          'Test capitalization',
          'Hello',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'returns false when output does not match regex' do
        result = evaluator.evaluate(
          'Test capitalization',
          'hello',
          expected: nil
        )

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
      end

      it 'handles regex with anchors' do
        anchored_evaluator = described_class.new(pattern: /\A\d{3}-\d{2}-\d{4}\z/)

        ssn_result = anchored_evaluator.evaluate(
          'Validate SSN',
          '123-45-6789',
          expected: nil
        )

        invalid_result = anchored_evaluator.evaluate(
          'Validate SSN',
          '123456789',
          expected: nil
        )

        expect(ssn_result[:value]).to eq(1)
        expect(invalid_result[:value]).to eq(0)
      end
    end

    context 'with capture groups' do
      let(:evaluator) { described_class.new(pattern: /(\d{4})-(\d{2})-(\d{2})/) }

      it 'matches patterns with groups' do
        result = evaluator.evaluate(
          'Extract date',
          'Date: 2024-01-15',
          expected: nil
        )

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Exact match')
      end

      it 'handles patterns with optional groups' do
        phone_evaluator = described_class.new(pattern: /\(?(\d{3})\)?[-.\s]?(\d{3})[-.\s]?(\d{4})/)

        formats = [
          '123-456-7890',
          '(123) 456-7890',
          '123.456.7890',
          '1234567890'
        ]

        results = formats.map do |phone|
          phone_evaluator.evaluate('Test phone', phone, expected: nil)
        end

        expect(results.map { |r| r[:value] }).to all(eq(1))
      end
    end

    it 'handles invalid regex patterns gracefully' do
      expect { described_class.new(pattern: '[invalid') }.to raise_error(RegexpError)
    end

    it 'handles nil output' do
      evaluator = described_class.new(pattern: /\d+/)

      result = evaluator.evaluate(
        'Test nil',
        nil,
        expected: nil
      )

      expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No match')
    end
  end
end

RSpec.describe 'Complex evaluation scenarios' do
  describe 'multiple evaluators combination' do
    it 'can use multiple evaluators for comprehensive assessment' do
      exact_evaluator = Langfuse::Evaluators::ExactMatchEvaluator.new
      length_evaluator = Langfuse::Evaluators::LengthEvaluator.new(min_length: 5, max_length: 50)
      contains_evaluator = Langfuse::Evaluators::ContainsEvaluator.new

      question = 'What is the capital of France?'
      output = 'The capital of France is Paris.'
      expected = 'Paris'

      exact_match = exact_evaluator.evaluate(question, output, expected: expected)
      length_check = length_evaluator.evaluate(question, output, expected: nil)
      contains_check = contains_evaluator.evaluate(question, output, expected: 'Paris')

      expect(exact_match[:value]).to eq(0)  # Not an exact match
      expect(length_check[:value]).to eq(1)   # Within length limits
      expect(contains_check[:value]).to eq(1) # Contains expected answer
    end
  end

  describe 'evaluation with different data types' do
    it 'handles evaluation of structured data' do
      exact_evaluator = Langfuse::Evaluators::ExactMatchEvaluator.new
      contains_evaluator = Langfuse::Evaluators::ContainsEvaluator.new

      json_output = '{"name": "John", "age": 30, "city": "New York"}'
      expected_json = '{"name": "John", "age": 30, "city": "New York"}'

      exact_result = exact_evaluator.evaluate('Test JSON', json_output, expected: expected_json)
      contains_result = contains_evaluator.evaluate('Test JSON', json_output, expected: '"name": "John"')

      expect(exact_result[:value]).to eq(1)
      expect(contains_result[:value]).to eq(1)
    end
  end
end