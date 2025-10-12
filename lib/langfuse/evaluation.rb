# frozen_string_literal: true

module Langfuse
  class Evaluation
    attr_reader :id, :name, :value, :data_type, :comment, :trace_id, :observation_id, :created_at

    def initialize(data)
      @data = data.is_a?(Hash) ? Utils.deep_symbolize_keys(data) : data

      @id = @data[:id]
      @name = @data[:name]
      @value = @data[:value]
      @data_type = @data[:data_type]
      @comment = @data[:comment]
      @trace_id = @data[:trace_id]
      @observation_id = @data[:observation_id]
      @created_at = @data[:created_at]
    end

    def to_dict
      {
        id: @id,
        name: @name,
        value: @value,
        data_type: @data_type,
        comment: @comment,
        trace_id: @trace_id,
        observation_id: @observation_id,
        created_at: @created_at
      }.compact
    end
  end

  class Score
    attr_reader :id, :name, :value, :data_type, :comment, :trace_id, :observation_id, :created_at

    def initialize(data)
      @data = data.is_a?(Hash) ? Utils.deep_symbolize_keys(data) : data

      @id = @data[:id]
      @name = @data[:name]
      @value = @data[:value]
      @data_type = @data[:data_type]
      @comment = @data[:comment]
      @trace_id = @data[:trace_id]
      @observation_id = @data[:observation_id]
      @created_at = @data[:created_at]
    end

    def to_dict
      {
        id: @id,
        name: @name,
        value: @value,
        data_type: @data_type,
        comment: @comment,
        trace_id: @trace_id,
        observation_id: @observation_id,
        created_at: @created_at
      }.compact
    end
  end

  module Evaluators
    class BaseEvaluator
      def initialize(name:, description: nil)
        @name = name
        @description = description
      end

      def evaluate(input, output, expected: nil, context: nil)
        raise NotImplementedError, 'Subclasses must implement evaluate method'
      end

      protected

      def create_score(value:, data_type: 'NUMERIC', comment: nil)
        {
          name: @name,
          value: value,
          data_type: data_type,
          comment: comment
        }
      end
    end

    class ExactMatchEvaluator < BaseEvaluator
      def initialize(name: 'exact_match', description: 'Exact match evaluator')
        super(name: name, description: description)
      end

      def evaluate(_input, output, expected: nil, context: nil)
        return create_score(value: 0, comment: 'No expected value provided') unless expected

        score = output.to_s.strip == expected.to_s.strip ? 1 : 0
        create_score(
          value: score,
          comment: score == 1 ? 'Exact match' : 'No match'
        )
      end
    end

    class ContainsEvaluator < BaseEvaluator
      def initialize(name: 'contains', description: 'Contains evaluator', case_sensitive: false)
        super(name: name, description: description)
        @case_sensitive = case_sensitive
      end

      def evaluate(_input, output, expected: nil, context: nil)
        return create_score(value: 0, comment: 'No expected value provided') unless expected

        output_str = @case_sensitive ? output.to_s : output.to_s.downcase
        expected_str = @case_sensitive ? expected.to_s : expected.to_s.downcase

        score = output_str.include?(expected_str) ? 1 : 0
        create_score(
          value: score,
          comment: score == 1 ? 'Contains expected text' : 'Does not contain expected text'
        )
      end
    end

    class LengthEvaluator < BaseEvaluator
      def initialize(name: 'length', description: 'Length evaluator', min_length: nil, max_length: nil)
        super(name: name, description: description)
        @min_length = min_length
        @max_length = max_length
      end

      def evaluate(_input, output, expected: nil, context: nil)
        length = output.to_s.length

        if @min_length && @max_length
          score = length >= @min_length && length <= @max_length ? 1 : 0
          comment = score == 1 ? "Length #{length} within range" : "Length #{length} outside range #{@min_length}-#{@max_length}"
        elsif @min_length
          score = length >= @min_length ? 1 : 0
          comment = score == 1 ? "Length #{length} meets minimum" : "Length #{length} below minimum #{@min_length}"
        elsif @max_length
          score = length <= @max_length ? 1 : 0
          comment = score == 1 ? "Length #{length} within maximum" : "Length #{length} exceeds maximum #{@max_length}"
        else
          score = length
          comment = "Length: #{length}"
        end

        create_score(
          value: score,
          data_type: 'NUMERIC',
          comment: comment
        )
      end
    end

    class RegexEvaluator < BaseEvaluator
      def initialize(pattern:, name: 'regex', description: 'Regex evaluator')
        super(name: name, description: description)
        @pattern = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
      end

      def evaluate(_input, output, expected: nil, context: nil)
        match = @pattern.match(output.to_s)
        score = match ? 1 : 0

        create_score(
          value: score,
          comment: score == 1 ? 'Regex pattern matched' : 'Regex pattern not matched'
        )
      end
    end

    class SimilarityEvaluator < BaseEvaluator
      def initialize(name: 'similarity', description: 'Similarity evaluator')
        super(name: name, description: description)
      end

      def evaluate(_input, output, expected: nil, context: nil)
        return create_score(value: 0, comment: 'No expected value provided') unless expected

        # Simple character-based similarity (Levenshtein distance)
        similarity = calculate_similarity(output.to_s, expected.to_s)

        create_score(
          value: similarity,
          data_type: 'NUMERIC',
          comment: "Similarity: #{(similarity * 100).round(2)}%"
        )
      end

      private

      def calculate_similarity(str1, str2)
        return 1.0 if str1 == str2
        return 0.0 if str1.empty? || str2.empty?

        distance = levenshtein_distance(str1, str2)
        max_length = [str1.length, str2.length].max

        1.0 - (distance.to_f / max_length)
      end

      def levenshtein_distance(str1, str2)
        matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

        (0..str1.length).each { |i| matrix[i][0] = i }
        (0..str2.length).each { |j| matrix[0][j] = j }

        (1..str1.length).each do |i|
          (1..str2.length).each do |j|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,     # deletion
              matrix[i][j - 1] + 1,     # insertion
              matrix[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        matrix[str1.length][str2.length]
      end
    end

    class LLMEvaluator < BaseEvaluator
      def initialize(client:, name: 'llm_evaluator', description: 'LLM-based evaluator', model: 'gpt-3.5-turbo',
                     prompt_template: nil)
        super(name: name, description: description)
        @client = client
        @model = model
        @prompt_template = prompt_template || default_prompt_template
      end

      def evaluate(input, output, expected: nil, context: nil)
        # This is a placeholder for LLM-based evaluation
        # In a real implementation, you would call an LLM API here
        @prompt_template.gsub('{input}', input.to_s)
                        .gsub('{output}', output.to_s)
                        .gsub('{expected}', expected.to_s)
                        .gsub('{context}', context.to_s)

        # Simulate LLM response (in real implementation, call actual LLM)
        score = rand(0.0..1.0).round(2)

        create_score(
          value: score,
          data_type: 'NUMERIC',
          comment: "LLM evaluation score: #{score}"
        )
      end

      private

      def default_prompt_template
        <<~PROMPT
          Please evaluate the following response:

          Input: {input}
          Output: {output}
          Expected: {expected}
          Context: {context}

          Rate the quality of the output on a scale from 0 to 1, where:
          - 0 = Poor quality, incorrect or irrelevant
          - 1 = Excellent quality, accurate and relevant

          Provide only the numeric score.
        PROMPT
      end
    end
  end
end
