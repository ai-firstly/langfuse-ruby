# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Trace do
  let(:client) { Langfuse::Client.new(public_key: 'test_key', secret_key: 'test_secret', debug: false) }
  let(:trace) { client.trace(name: 'test-trace', user_id: 'test-user', input: { message: 'Hello, world!' }) }

  describe 'initialization' do
    it 'creates a trace with basic attributes' do
      expect(trace).to be_a(Langfuse::Trace)
      expect(trace.name).to eq('test-trace')
      expect(trace.user_id).to eq('test-user')
      expect(trace.input).to eq({ message: 'Hello, world!' })
      expect(trace.id).not_to be_nil
    end

    it 'generates a unique trace ID' do
      trace2 = client.trace(name: 'another-trace')
      expect(trace.id).not_to eq(trace2.id)
    end
  end

  describe 'span operations' do
    it 'creates a nested span' do
      span = trace.span(name: 'test-span', input: { query: 'test' })

      expect(span).to be_a(Langfuse::Span)
      expect(span.name).to eq('test-span')
      expect(span.trace_id).to eq(trace.id)
      expect(span.input).to eq({ query: 'test' })
    end

    it 'supports method chaining' do
      span = trace.span(name: 'chained-span')
             .span(name: 'nested-span')

      expect(span).to be_a(Langfuse::Span)
      expect(span.name).to eq('nested-span')
    end
  end

  describe 'generation operations' do
    it 'creates a generation within trace' do
      generation = trace.generation(
        name: 'test-generation',
        model: 'gpt-3.5-turbo',
        input: [{ role: 'user', content: 'Hello!' }],
        output: { content: 'Hi there!' }
      )

      expect(generation).to be_a(Langfuse::Generation)
      expect(generation.name).to eq('test-generation')
      expect(generation.model).to eq('gpt-3.5-turbo')
      expect(generation.trace_id).to eq(trace.id)
    end

    it 'supports nested generation in spans' do
      span = trace.span(name: 'parent-span')
      generation = span.generation(
        name: 'nested-generation',
        model: 'gpt-4',
        input: 'test input',
        output: 'test output'
      )

      expect(generation.trace_id).to eq(trace.id)
    end
  end

  describe 'event operations' do
    it 'creates an event within trace' do
      event = trace.event(name: 'test-event', input: { action: 'click' })

      expect(event).to be_a(Langfuse::Event)
      expect(event.name).to eq('test-event')
      expect(event.trace_id).to eq(trace.id)
    end
  end

  describe 'scoring operations' do
    it 'creates a score for the trace' do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
        name: 'trace-score',
        value: 0.8,
        trace_id: trace.id
      ))

      trace.score(name: 'trace-score', value: 0.8)
    end

    it 'creates a score with data type' do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
        name: 'categorical-score',
        value: 'good',
        data_type: 'CATEGORICAL',
        trace_id: trace.id
      ))

      trace.score(name: 'categorical-score', value: 'good', data_type: 'CATEGORICAL')
    end
  end

  describe 'complex workflow' do
    it 'supports complex nested operations' do
      complex_trace = client.trace(
        name: 'complex-workflow',
        user_id: 'user-456',
        session_id: 'session-789',
        input: { query: 'Explain quantum computing' },
        environment: 'test',
        metadata: {
          version: '1.0.0',
          tags: %w[physics computing]
        }
      )

      # Document retrieval span
      retrieval_span = complex_trace.span(
        name: 'document-retrieval',
        input: { query: 'quantum computing basics' }
      )

      # Embedding generation
      embedding_gen = retrieval_span.generation(
        name: 'embedding-generation',
        model: 'text-embedding-ada-002',
        input: 'quantum computing basics',
        output: Array.new(1536) { rand(-1.0..1.0) },
        usage: { prompt_tokens: 4, total_tokens: 4 }
      )

      # Answer generation span
      answer_span = complex_trace.span(
        name: 'answer-generation',
        input: {
          query: 'Explain quantum computing',
          context: ['Quantum computing uses quantum bits...']
        }
      )

      # LLM generation
      llm_gen = answer_span.generation(
        name: 'openai-completion',
        model: 'gpt-4',
        input: [
          { role: 'system', content: 'You are a physics expert.' },
          { role: 'user', content: 'Explain quantum computing based on the context.' }
        ],
        output: {
          content: 'Quantum computing is a revolutionary approach...'
        },
        usage: {
          prompt_tokens: 120,
          completion_tokens: 45,
          total_tokens: 165
        },
        model_parameters: {
          temperature: 0.7,
          max_tokens: 200
        }
      )

      expect(complex_trace.name).to eq('complex-workflow')
      expect(retrieval_span.name).to eq('document-retrieval')
      expect(embedding_gen.model).to eq('text-embedding-ada-002')
      expect(answer_span.name).to eq('answer-generation')
      expect(llm_gen.model).to eq('gpt-4')
    end
  end

  describe 'trace updates' do
    it 'updates trace attributes' do
      # Verify the first update was enqueued
      expect(client).to receive(:enqueue_event).with('trace-update', hash_including(
        id: trace.id,
        output: { answer: 'Test response' },
        status: 'success'
      ))

      trace.update(
        output: { answer: 'Test response' },
        end_time: Time.now.iso8601,
        status: 'success'
      )

      # Verify the second update was enqueued
      expect(client).to receive(:enqueue_event).with('trace-update', hash_including(
        id: trace.id,
        output: { answer: 'Updated response' }
      ))

      trace.update(output: { answer: 'Updated response' })
    end
  end

  describe 'trace ending' do
    it 'ends the trace with output' do
      expect(client).to receive(:enqueue_event).with('trace-update', hash_including(
        id: trace.id,
        output: { result: 'completed' },
        status: 'success'
      ))

      trace.end(output: { result: 'completed' }, status: 'success')
    end
  end
end