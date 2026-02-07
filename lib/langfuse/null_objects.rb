# frozen_string_literal: true

module Langfuse
  # NullGeneration provides a no-op generation object for graceful degradation.
  # Used when Langfuse is unavailable or trace creation fails.
  class NullGeneration
    def update(**) = self
    def end(**) = self
    def span(**) = NullSpan.new
    def generation(**) = NullGeneration.new
    def event(**) = NullEvent.new
    def agent(**) = NullSpan.new
    def tool(**) = NullSpan.new
    def chain(**) = NullSpan.new
    def retriever(**) = NullSpan.new
    def embedding(**) = NullSpan.new
    def evaluator(**) = NullSpan.new
    def guardrail(**) = NullSpan.new
    def score(**) = nil
    def get_url = nil
    def to_dict = {}
    def id = nil
    def trace_id = nil
  end

  # NullSpan provides a no-op span object for graceful degradation.
  class NullSpan
    def update(**) = self
    def end(**) = self
    def span(**) = NullSpan.new
    def generation(**) = NullGeneration.new
    def event(**) = NullEvent.new
    def agent(**) = NullSpan.new
    def tool(**) = NullSpan.new
    def chain(**) = NullSpan.new
    def retriever(**) = NullSpan.new
    def embedding(**) = NullSpan.new
    def evaluator(**) = NullSpan.new
    def guardrail(**) = NullSpan.new
    def score(**) = nil
    def get_url = nil
    def to_dict = {}
    def id = nil
    def trace_id = nil
  end

  # NullEvent provides a no-op event object for graceful degradation.
  class NullEvent
    def to_dict = {}
    def id = nil
    def trace_id = nil
  end

  # NullTrace provides a no-op trace object for graceful degradation.
  # Used when Langfuse is unavailable or trace creation fails.
  # Ensures calling code doesn't break when Langfuse has issues.
  class NullTrace
    def update(**) = self
    def span(**) = NullSpan.new
    def generation(**) = NullGeneration.new
    def event(**) = NullEvent.new
    def agent(**) = NullSpan.new
    def tool(**) = NullSpan.new
    def chain(**) = NullSpan.new
    def retriever(**) = NullSpan.new
    def embedding(**) = NullSpan.new
    def evaluator(**) = NullSpan.new
    def guardrail(**) = NullSpan.new
    def score(**) = nil
    def get_url = nil
    def to_dict = {}
    def id = nil
  end
end
