# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Evaluation and Evaluators' do
  describe Langfuse::Evaluation do
    let(:data) do
      {
        id: 'eval-1',
        name: 'accuracy',
        value: 0.95,
        data_type: 'NUMERIC',
        comment: 'Good match',
        trace_id: 'trace-1',
        observation_id: 'obs-1',
        created_at: '2026-03-28T00:00:00Z'
      }
    end

    it 'initializes with a symbol-keyed hash' do
      eval = Langfuse::Evaluation.new(data)

      expect(eval.id).to eq('eval-1')
      expect(eval.name).to eq('accuracy')
      expect(eval.value).to eq(0.95)
      expect(eval.data_type).to eq('NUMERIC')
      expect(eval.comment).to eq('Good match')
      expect(eval.trace_id).to eq('trace-1')
      expect(eval.observation_id).to eq('obs-1')
      expect(eval.created_at).to eq('2026-03-28T00:00:00Z')
    end

    it 'initializes with a string-keyed hash' do
      string_data = {
        'id' => 'eval-2',
        'name' => 'relevance',
        'value' => 1,
        'trace_id' => 'trace-2'
      }
      eval = Langfuse::Evaluation.new(string_data)

      expect(eval.id).to eq('eval-2')
      expect(eval.name).to eq('relevance')
      expect(eval.value).to eq(1)
      expect(eval.trace_id).to eq('trace-2')
    end

    describe '#to_dict' do
      it 'returns a hash with all populated fields' do
        eval = Langfuse::Evaluation.new(data)
        dict = eval.to_dict

        expect(dict).to eq(data)
      end

      it 'omits nil fields via compact' do
        eval = Langfuse::Evaluation.new(id: 'eval-3', name: 'test')
        dict = eval.to_dict

        expect(dict).to eq({ id: 'eval-3', name: 'test' })
        expect(dict).not_to have_key(:value)
        expect(dict).not_to have_key(:comment)
        expect(dict).not_to have_key(:trace_id)
      end
    end
  end

  describe Langfuse::Score do
    let(:data) do
      {
        id: 'score-1',
        name: 'quality',
        value: 0.8,
        data_type: 'NUMERIC',
        comment: 'Decent',
        trace_id: 'trace-1',
        observation_id: 'obs-1',
        created_at: '2026-03-28T00:00:00Z'
      }
    end

    it 'initializes with a symbol-keyed hash' do
      score = Langfuse::Score.new(data)

      expect(score.id).to eq('score-1')
      expect(score.name).to eq('quality')
      expect(score.value).to eq(0.8)
      expect(score.data_type).to eq('NUMERIC')
      expect(score.comment).to eq('Decent')
      expect(score.trace_id).to eq('trace-1')
      expect(score.observation_id).to eq('obs-1')
      expect(score.created_at).to eq('2026-03-28T00:00:00Z')
    end

    it 'initializes with a string-keyed hash' do
      score = Langfuse::Score.new('id' => 'score-2', 'name' => 'relevance')

      expect(score.id).to eq('score-2')
      expect(score.name).to eq('relevance')
    end

    describe '#to_dict' do
      it 'returns a hash with all populated fields' do
        score = Langfuse::Score.new(data)

        expect(score.to_dict).to eq(data)
      end

      it 'omits nil fields via compact' do
        score = Langfuse::Score.new(id: 'score-3')
        dict = score.to_dict

        expect(dict).to eq({ id: 'score-3' })
      end
    end
  end

  describe Langfuse::Evaluators::BaseEvaluator do
    it 'raises NotImplementedError on evaluate' do
      evaluator = Langfuse::Evaluators::BaseEvaluator.new(name: 'base')

      expect { evaluator.evaluate('input', 'output') }
        .to raise_error(NotImplementedError, 'Subclasses must implement evaluate method')
    end
  end

  describe Langfuse::Evaluators::ExactMatchEvaluator do
    let(:evaluator) { Langfuse::Evaluators::ExactMatchEvaluator.new }

    it 'returns score 1 for exact match' do
      result = evaluator.evaluate('input', 'hello', expected: 'hello')

      expect(result[:value]).to eq(1)
      expect(result[:name]).to eq('exact_match')
      expect(result[:comment]).to eq('Exact match')
    end

    it 'returns score 1 with leading/trailing whitespace differences' do
      result = evaluator.evaluate('input', '  hello  ', expected: 'hello')

      expect(result[:value]).to eq(1)
    end

    it 'returns score 0 for no match' do
      result = evaluator.evaluate('input', 'hello', expected: 'world')

      expect(result[:value]).to eq(0)
      expect(result[:comment]).to eq('No match')
    end

    it 'returns score 0 when expected is nil' do
      result = evaluator.evaluate('input', 'hello')

      expect(result[:value]).to eq(0)
      expect(result[:comment]).to eq('No expected value provided')
    end

    it 'converts values to strings for comparison' do
      result = evaluator.evaluate('input', 42, expected: '42')

      expect(result[:value]).to eq(1)
    end

    it 'uses default name and data_type' do
      result = evaluator.evaluate('input', 'x', expected: 'x')

      expect(result[:name]).to eq('exact_match')
      expect(result[:data_type]).to eq('NUMERIC')
    end
  end

  describe Langfuse::Evaluators::ContainsEvaluator do
    context 'case insensitive (default)' do
      let(:evaluator) { Langfuse::Evaluators::ContainsEvaluator.new }

      it 'returns score 1 when output contains expected (case insensitive)' do
        result = evaluator.evaluate('input', 'Hello World', expected: 'hello')

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Contains expected text')
      end

      it 'returns score 0 when output does not contain expected' do
        result = evaluator.evaluate('input', 'Hello World', expected: 'foo')

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('Does not contain expected text')
      end

      it 'returns score 0 when expected is nil' do
        result = evaluator.evaluate('input', 'Hello')

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('No expected value provided')
      end
    end

    context 'case sensitive' do
      let(:evaluator) { Langfuse::Evaluators::ContainsEvaluator.new(case_sensitive: true) }

      it 'returns score 1 for case-exact substring' do
        result = evaluator.evaluate('input', 'Hello World', expected: 'Hello')

        expect(result[:value]).to eq(1)
      end

      it 'returns score 0 when case does not match' do
        result = evaluator.evaluate('input', 'Hello World', expected: 'hello')

        expect(result[:value]).to eq(0)
      end
    end
  end

  describe Langfuse::Evaluators::LengthEvaluator do
    context 'with min_length and max_length' do
      let(:evaluator) { Langfuse::Evaluators::LengthEvaluator.new(min_length: 5, max_length: 10) }

      it 'returns score 1 when length is within range' do
        result = evaluator.evaluate('input', 'abcdef')

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Length 6 within range')
      end

      it 'returns score 0 when length is below range' do
        result = evaluator.evaluate('input', 'abc')

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('Length 3 outside range 5-10')
      end

      it 'returns score 0 when length is above range' do
        result = evaluator.evaluate('input', 'a' * 15)

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('Length 15 outside range 5-10')
      end

      it 'returns score 1 at boundary values' do
        expect(evaluator.evaluate('input', 'a' * 5)[:value]).to eq(1)
        expect(evaluator.evaluate('input', 'a' * 10)[:value]).to eq(1)
      end
    end

    context 'with min_length only' do
      let(:evaluator) { Langfuse::Evaluators::LengthEvaluator.new(min_length: 5) }

      it 'returns score 1 when length meets minimum' do
        result = evaluator.evaluate('input', 'abcde')

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Length 5 meets minimum')
      end

      it 'returns score 0 when length is below minimum' do
        result = evaluator.evaluate('input', 'abc')

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('Length 3 below minimum 5')
      end
    end

    context 'with max_length only' do
      let(:evaluator) { Langfuse::Evaluators::LengthEvaluator.new(max_length: 10) }

      it 'returns score 1 when length is within maximum' do
        result = evaluator.evaluate('input', 'abcde')

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Length 5 within maximum')
      end

      it 'returns score 0 when length exceeds maximum' do
        result = evaluator.evaluate('input', 'a' * 15)

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('Length 15 exceeds maximum 10')
      end
    end

    context 'with neither min_length nor max_length' do
      let(:evaluator) { Langfuse::Evaluators::LengthEvaluator.new }

      it 'returns the raw length as the score' do
        result = evaluator.evaluate('input', 'hello')

        expect(result[:value]).to eq(5)
        expect(result[:comment]).to eq('Length: 5')
      end
    end
  end

  describe Langfuse::Evaluators::RegexEvaluator do
    context 'with a string pattern' do
      let(:evaluator) { Langfuse::Evaluators::RegexEvaluator.new(pattern: '\\d+') }

      it 'returns score 1 when pattern matches' do
        result = evaluator.evaluate('input', 'abc123')

        expect(result[:value]).to eq(1)
        expect(result[:comment]).to eq('Regex pattern matched')
      end

      it 'returns score 0 when pattern does not match' do
        result = evaluator.evaluate('input', 'abcdef')

        expect(result[:value]).to eq(0)
        expect(result[:comment]).to eq('Regex pattern not matched')
      end
    end

    context 'with a Regexp pattern' do
      let(:evaluator) { Langfuse::Evaluators::RegexEvaluator.new(pattern: /^hello/i) }

      it 'returns score 1 when pattern matches' do
        result = evaluator.evaluate('input', 'Hello World')

        expect(result[:value]).to eq(1)
      end

      it 'returns score 0 when pattern does not match' do
        result = evaluator.evaluate('input', 'World Hello')

        expect(result[:value]).to eq(0)
      end
    end
  end

  describe Langfuse::Evaluators::SimilarityEvaluator do
    let(:evaluator) { Langfuse::Evaluators::SimilarityEvaluator.new }

    it 'returns similarity 1.0 for identical strings' do
      result = evaluator.evaluate('input', 'hello', expected: 'hello')

      expect(result[:value]).to eq(1.0)
      expect(result[:comment]).to eq('Similarity: 100.0%')
    end

    it 'returns similarity 0.0 when expected is nil' do
      result = evaluator.evaluate('input', 'hello')

      expect(result[:value]).to eq(0)
      expect(result[:comment]).to eq('No expected value provided')
    end

    it 'returns similarity 0.0 for empty output with non-empty expected' do
      result = evaluator.evaluate('input', '', expected: 'hello')

      expect(result[:value]).to eq(0.0)
    end

    it 'returns similarity 0.0 for non-empty output with empty expected' do
      result = evaluator.evaluate('input', 'hello', expected: '')

      expect(result[:value]).to eq(0.0)
    end

    it 'returns partial similarity for similar strings' do
      result = evaluator.evaluate('input', 'kitten', expected: 'sitting')

      expect(result[:value]).to be > 0.0
      expect(result[:value]).to be < 1.0
      expect(result[:data_type]).to eq('NUMERIC')
    end

    it 'computes correct Levenshtein-based similarity' do
      # "cat" vs "car" => distance 1, max_length 3, similarity = 1 - 1/3 ≈ 0.6667
      result = evaluator.evaluate('input', 'cat', expected: 'car')

      expected_similarity = (1.0 - (1.0 / 3)).round(2)
      expect(result[:value].round(2)).to eq(expected_similarity)
    end
  end

  describe Langfuse::Evaluators::LLMEvaluator do
    let(:client) do
      Langfuse::Client.new(
        public_key: 'test_key',
        secret_key: 'test_secret',
        host: 'https://test.langfuse.com',
        auto_flush: false
      )
    end
    let(:evaluator) { Langfuse::Evaluators::LLMEvaluator.new(client: client) }

    it 'has a default_prompt_template containing placeholders' do
      custom_evaluator = Langfuse::Evaluators::LLMEvaluator.new(client: client)
      result = custom_evaluator.evaluate('my input', 'my output', expected: 'my expected', context: 'my context')

      expect(result[:name]).to eq('llm_evaluator')
      expect(result[:data_type]).to eq('NUMERIC')
      expect(result[:value]).to be_a(Float)
      expect(result[:value]).to be >= 0.0
      expect(result[:value]).to be <= 1.0
    end

    it 'returns a score hash with correct structure' do
      result = evaluator.evaluate('input', 'output', expected: 'expected')

      expect(result).to have_key(:name)
      expect(result).to have_key(:value)
      expect(result).to have_key(:data_type)
      expect(result).to have_key(:comment)
      expect(result[:comment]).to match(/LLM evaluation score:/)
    end

    it 'accepts a custom prompt_template' do
      custom_template = 'Rate: {input} -> {output} (expected: {expected}, context: {context})'
      custom_evaluator = Langfuse::Evaluators::LLMEvaluator.new(
        client: client,
        prompt_template: custom_template
      )
      result = custom_evaluator.evaluate('q', 'a', expected: 'e', context: 'c')

      expect(result[:value]).to be_a(Float)
    end

    it 'handles nil expected and context' do
      result = evaluator.evaluate('input', 'output')

      expect(result[:value]).to be_a(Float)
    end
  end
end
