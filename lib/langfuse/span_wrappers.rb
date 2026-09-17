# frozen_string_literal: true

module Langfuse
  # Defines the enhanced observation helpers (agent, tool, chain, retriever,
  # evaluator, guardrail) as thin wrappers around the extending class's #span,
  # each pinning a fixed as_type.
  #
  # `embedding` is intentionally not generated here: every wrapper folds
  # model/usage into metadata before delegating, so it stays hand-written.
  module SpanWrappers
    TYPES = {
      agent: ObservationType::AGENT,
      tool: ObservationType::TOOL,
      chain: ObservationType::CHAIN,
      retriever: ObservationType::RETRIEVER,
      evaluator: ObservationType::EVALUATOR,
      guardrail: ObservationType::GUARDRAIL
    }.freeze

    # `evaluator_name` exists because Client exposes the helper as
    # `evaluator_obs`, keeping it distinct from the Evaluators API.
    def define_span_wrappers(evaluator_name: :evaluator)
      TYPES.each do |name, as_type|
        method_name = name == :evaluator ? evaluator_name : name

        define_method(method_name) do |**kwargs|
          span(**kwargs, as_type: as_type)
        end
      end
    end
  end
end
