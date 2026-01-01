# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Enhanced Observation Types' do
  let(:client) do
    Langfuse::Client.new(
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com',
      auto_flush: false
    )
  end

  describe Langfuse::ObservationType do
    it 'defines all observation types' do
      expect(Langfuse::ObservationType::SPAN).to eq('span')
      expect(Langfuse::ObservationType::GENERATION).to eq('generation')
      expect(Langfuse::ObservationType::EVENT).to eq('event')
      expect(Langfuse::ObservationType::AGENT).to eq('agent')
      expect(Langfuse::ObservationType::TOOL).to eq('tool')
      expect(Langfuse::ObservationType::CHAIN).to eq('chain')
      expect(Langfuse::ObservationType::RETRIEVER).to eq('retriever')
      expect(Langfuse::ObservationType::EMBEDDING).to eq('embedding')
      expect(Langfuse::ObservationType::EVALUATOR).to eq('evaluator')
      expect(Langfuse::ObservationType::GUARDRAIL).to eq('guardrail')
    end

    it 'validates valid types' do
      Langfuse::ObservationType::ALL.each do |type|
        expect(Langfuse::ObservationType.valid?(type)).to be true
      end
    end

    it 'validates nil as valid (defaults to base type)' do
      expect(Langfuse::ObservationType.valid?(nil)).to be true
    end

    it 'invalidates unknown types' do
      expect(Langfuse::ObservationType.valid?('unknown')).to be false
    end

    it 'identifies span-based types' do
      expect(Langfuse::ObservationType.span_based?('span')).to be true
      expect(Langfuse::ObservationType.span_based?('agent')).to be true
      expect(Langfuse::ObservationType.span_based?('tool')).to be true
      expect(Langfuse::ObservationType.span_based?('generation')).to be false
      expect(Langfuse::ObservationType.span_based?('event')).to be false
    end
  end

  describe 'Span with as_type' do
    it 'creates a span with as_type parameter' do
      span = client.span(
        trace_id: 'test_trace',
        name: 'test_span',
        as_type: 'agent'
      )

      expect(span.as_type).to eq('agent')
      expect(span.to_dict[:type]).to eq('agent')
    end

    it 'raises error for invalid as_type' do
      expect do
        client.span(
          trace_id: 'test_trace',
          name: 'test_span',
          as_type: 'invalid_type'
        )
      end.to raise_error(Langfuse::ValidationError)
    end

    it 'allows nil as_type (defaults to span)' do
      span = client.span(
        trace_id: 'test_trace',
        name: 'test_span'
      )

      expect(span.as_type).to be_nil
      expect(span.to_dict[:type]).to be_nil
    end
  end

  describe 'Client convenience methods' do
    it 'creates an agent observation' do
      agent = client.agent(trace_id: 'test_trace', name: 'test_agent')

      expect(agent).to be_a(Langfuse::Span)
      expect(agent.as_type).to eq('agent')
      expect(agent.name).to eq('test_agent')
    end

    it 'creates a tool observation' do
      tool = client.tool(trace_id: 'test_trace', name: 'weather_api')

      expect(tool).to be_a(Langfuse::Span)
      expect(tool.as_type).to eq('tool')
      expect(tool.name).to eq('weather_api')
    end

    it 'creates a chain observation' do
      chain = client.chain(trace_id: 'test_trace', name: 'retrieval_chain')

      expect(chain).to be_a(Langfuse::Span)
      expect(chain.as_type).to eq('chain')
    end

    it 'creates a retriever observation' do
      retriever = client.retriever(
        trace_id: 'test_trace',
        name: 'vector_search',
        input: { query: 'test query', top_k: 5 }
      )

      expect(retriever).to be_a(Langfuse::Span)
      expect(retriever.as_type).to eq('retriever')
      expect(retriever.input).to eq({ query: 'test query', top_k: 5 })
    end

    it 'creates an embedding observation with model and usage' do
      embedding = client.embedding(
        trace_id: 'test_trace',
        name: 'document_embedding',
        input: ['text to embed'],
        model: 'text-embedding-ada-002',
        usage: { prompt_tokens: 10 }
      )

      expect(embedding).to be_a(Langfuse::Span)
      expect(embedding.as_type).to eq('embedding')
      expect(embedding.metadata[:model]).to eq('text-embedding-ada-002')
      expect(embedding.metadata[:usage]).to eq({ prompt_tokens: 10 })
    end

    it 'creates an evaluator observation' do
      evaluator = client.evaluator_obs(
        trace_id: 'test_trace',
        name: 'hallucination_check',
        input: { context: 'Paris is the capital of France', response: 'Paris' }
      )

      expect(evaluator).to be_a(Langfuse::Span)
      expect(evaluator.as_type).to eq('evaluator')
    end

    it 'creates a guardrail observation' do
      guardrail = client.guardrail(
        trace_id: 'test_trace',
        name: 'content_filter',
        input: { message: 'user input' },
        output: { blocked: false }
      )

      expect(guardrail).to be_a(Langfuse::Span)
      expect(guardrail.as_type).to eq('guardrail')
    end
  end

  describe 'Trace convenience methods' do
    let(:trace) { client.trace(name: 'test_trace') }

    it 'creates a child agent from trace' do
      agent = trace.agent(name: 'my_agent')

      expect(agent).to be_a(Langfuse::Span)
      expect(agent.as_type).to eq('agent')
      expect(agent.trace_id).to eq(trace.id)
    end

    it 'creates a child tool from trace' do
      tool = trace.tool(name: 'my_tool')

      expect(tool).to be_a(Langfuse::Span)
      expect(tool.as_type).to eq('tool')
    end

    it 'creates a child chain from trace' do
      chain = trace.chain(name: 'my_chain')

      expect(chain).to be_a(Langfuse::Span)
      expect(chain.as_type).to eq('chain')
    end

    it 'creates a child retriever from trace' do
      retriever = trace.retriever(name: 'my_retriever')

      expect(retriever).to be_a(Langfuse::Span)
      expect(retriever.as_type).to eq('retriever')
    end

    it 'creates a child embedding from trace' do
      embedding = trace.embedding(
        name: 'my_embedding',
        model: 'text-embedding-3-small'
      )

      expect(embedding).to be_a(Langfuse::Span)
      expect(embedding.as_type).to eq('embedding')
      expect(embedding.metadata[:model]).to eq('text-embedding-3-small')
    end

    it 'creates a child evaluator from trace' do
      evaluator = trace.evaluator(name: 'my_evaluator')

      expect(evaluator).to be_a(Langfuse::Span)
      expect(evaluator.as_type).to eq('evaluator')
    end

    it 'creates a child guardrail from trace' do
      guardrail = trace.guardrail(name: 'my_guardrail')

      expect(guardrail).to be_a(Langfuse::Span)
      expect(guardrail.as_type).to eq('guardrail')
    end
  end

  describe 'Span convenience methods' do
    let(:trace) { client.trace(name: 'test_trace') }
    let(:span) { trace.span(name: 'parent_span') }

    it 'creates nested agent from span' do
      agent = span.agent(name: 'nested_agent')

      expect(agent.as_type).to eq('agent')
      expect(agent.parent_observation_id).to eq(span.id)
    end

    it 'creates nested tool from span' do
      tool = span.tool(name: 'nested_tool')

      expect(tool.as_type).to eq('tool')
      expect(tool.parent_observation_id).to eq(span.id)
    end

    it 'creates nested chain from span' do
      chain = span.chain(name: 'nested_chain')

      expect(chain.as_type).to eq('chain')
      expect(chain.parent_observation_id).to eq(span.id)
    end

    it 'creates nested retriever from span' do
      retriever = span.retriever(name: 'nested_retriever')

      expect(retriever.as_type).to eq('retriever')
    end

    it 'creates nested embedding from span' do
      embedding = span.embedding(name: 'nested_embedding')

      expect(embedding.as_type).to eq('embedding')
    end

    it 'creates nested evaluator from span' do
      evaluator = span.evaluator(name: 'nested_evaluator')

      expect(evaluator.as_type).to eq('evaluator')
    end

    it 'creates nested guardrail from span' do
      guardrail = span.guardrail(name: 'nested_guardrail')

      expect(guardrail.as_type).to eq('guardrail')
    end
  end

  describe 'Generation convenience methods' do
    let(:trace) { client.trace(name: 'test_trace') }
    let(:generation) { trace.generation(name: 'parent_gen', model: 'gpt-4') }

    it 'creates nested tool from generation' do
      tool = generation.tool(name: 'tool_call')

      expect(tool.as_type).to eq('tool')
      expect(tool.parent_observation_id).to eq(generation.id)
    end

    it 'creates nested embedding from generation' do
      embedding = generation.embedding(
        name: 'context_embedding',
        model: 'text-embedding-ada-002'
      )

      expect(embedding.as_type).to eq('embedding')
      expect(embedding.parent_observation_id).to eq(generation.id)
    end
  end

  describe 'Event with as_type' do
    it 'creates an event with as_type parameter' do
      event = client.event(
        trace_id: 'test_trace',
        name: 'test_event',
        as_type: 'tool'
      )

      expect(event.as_type).to eq('tool')
      expect(event.to_dict[:type]).to eq('tool')
    end
  end

  describe 'Complex workflow with enhanced types' do
    it 'creates a full agent workflow trace' do
      trace = client.trace(
        name: 'restaurant_booking_agent',
        input: { task: 'Book a restaurant' }
      )

      # Agent observation
      agent = trace.agent(
        name: 'booking_agent',
        input: { task: 'Book Italian restaurant in NYC' },
        metadata: { agent_type: 'planning', tools: %w[search book] }
      )

      # Guardrail check
      guardrail = agent.guardrail(
        name: 'input_safety_check',
        input: { message: 'Book Italian restaurant in NYC' },
        output: { blocked: false, reason: nil }
      )
      guardrail.end

      # Tool call - search
      search_tool = agent.tool(
        name: 'restaurant_search',
        input: { location: 'NYC', cuisine: 'Italian' }
      )
      search_tool.update(output: { restaurants: ["Mario's", "Luigi's"] })
      search_tool.end

      # Embedding for semantic search
      embedding = agent.embedding(
        name: 'query_embedding',
        input: ['Italian restaurant NYC'],
        model: 'text-embedding-ada-002',
        usage: { prompt_tokens: 5 }
      )
      embedding.end(output: [[0.1, 0.2, 0.3]])

      # Retriever for context
      retriever = agent.retriever(
        name: 'restaurant_reviews',
        input: { query: "Mario's reviews", top_k: 3 },
        metadata: { index: 'reviews', similarity: 'cosine' }
      )
      retriever.end(output: { documents: %w[review1 review2 review3] })

      # LLM generation
      gen = agent.generation(
        name: 'decision_making',
        model: 'gpt-4',
        input: [{ role: 'user', content: 'Which restaurant?' }]
      )
      gen.end(output: "I recommend Mario's", usage: { prompt_tokens: 50, completion_tokens: 20 })

      # Tool call - booking
      book_tool = agent.tool(
        name: 'make_reservation',
        input: { restaurant: "Mario's", time: '7:00 PM', party_size: 4 }
      )
      book_tool.end(output: { confirmed: true, reservation_id: 'RES123' })

      # Evaluator
      evaluator = agent.evaluator(
        name: 'success_check',
        input: { expected: 'reservation', actual: { confirmed: true } },
        output: { score: 1.0, passed: true }
      )
      evaluator.end

      # Complete agent
      agent.end(output: { success: true, reservation_id: 'RES123' })

      # Update trace with final output
      trace.update(output: { reservation_id: 'RES123', status: 'confirmed' })

      # Verify structure
      expect(agent.as_type).to eq('agent')
      expect(guardrail.as_type).to eq('guardrail')
      expect(search_tool.as_type).to eq('tool')
      expect(embedding.as_type).to eq('embedding')
      expect(retriever.as_type).to eq('retriever')
      expect(book_tool.as_type).to eq('tool')
      expect(evaluator.as_type).to eq('evaluator')
    end
  end
end
