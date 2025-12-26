# frozen_string_literal: true

module Langfuse
  # Valid observation types for Langfuse
  # These types provide semantic meaning to observations in traces
  module ObservationType
    # Core observation types (existing)
    SPAN = 'span'
    GENERATION = 'generation'
    EVENT = 'event'

    # Enhanced observation types (new in 2025)
    AGENT = 'agent'           # Agent workflows and reasoning
    TOOL = 'tool'             # Tool/function calls
    CHAIN = 'chain'           # Chain operations (e.g., retrieval chains)
    RETRIEVER = 'retriever'   # Data retrieval (vector stores, databases)
    EMBEDDING = 'embedding'   # Embedding generation
    EVALUATOR = 'evaluator'   # Evaluation/scoring functions
    GUARDRAIL = 'guardrail'   # Safety filters and content moderation

    # All valid observation types
    ALL = [
      SPAN,
      GENERATION,
      EVENT,
      AGENT,
      TOOL,
      CHAIN,
      RETRIEVER,
      EMBEDDING,
      EVALUATOR,
      GUARDRAIL
    ].freeze

    # Types that are aliases for span (use span-create/span-update events)
    SPAN_BASED = [
      SPAN,
      AGENT,
      TOOL,
      CHAIN,
      RETRIEVER,
      EMBEDDING,
      EVALUATOR,
      GUARDRAIL
    ].freeze

    # Validate if a type is valid
    def self.valid?(type)
      return true if type.nil? # nil is valid (defaults to base type)

      ALL.include?(type.to_s)
    end

    # Check if type uses span events
    def self.span_based?(type)
      return true if type.nil?

      SPAN_BASED.include?(type.to_s)
    end
  end
end
