# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Span do
  let(:client) { Langfuse::Client.new(public_key: 'test_key', secret_key: 'test_secret', debug: false) }
  let(:trace) { client.trace(name: 'parent-trace') }
  let(:span) { trace.span(name: 'test-span', input: { query: 'test query' }) }

  describe 'initialization' do
    it 'creates a span with basic attributes' do
      expect(span).to be_a(Langfuse::Span)
      expect(span.name).to eq('test-span')
      expect(span.input).to eq({ query: 'test query' })
      expect(span.trace_id).to eq(trace.id)
      expect(span.id).not_to be_nil
    end

    it 'creates a span directly with trace_id' do
      direct_span = client.span(trace_id: 'test-trace-id', name: 'direct-span')
      expect(direct_span.trace_id).to eq('test-trace-id')
      expect(direct_span.name).to eq('direct-span')
    end
  end

  describe 'nested operations' do
    it 'creates nested spans' do
      nested_span = span.span(name: 'nested-span')
      expect(nested_span).to be_a(Langfuse::Span)
      expect(nested_span.trace_id).to eq(trace.id)
      expect(nested_span.name).to eq('nested-span')
    end

    it 'creates generations within span' do
      generation = span.generation(
        name: 'span-generation',
        model: 'gpt-3.5-turbo',
        input: 'test input',
        output: 'test output'
      )

      expect(generation).to be_a(Langfuse::Generation)
      expect(generation.trace_id).to eq(trace.id)
      expect(generation.name).to eq('span-generation')
    end

    it 'creates events within span' do
      event = span.event(name: 'span-event', input: { action: 'process' })
      expect(event).to be_a(Langfuse::Event)
      expect(event.trace_id).to eq(trace.id)
      expect(event.name).to eq('span-event')
    end
  end

  describe 'span updates' do
    it 'updates span attributes' do
      expect(client).to receive(:enqueue_event).with('span-update', hash_including(
        id: span.id,
        output: { result: 'span completed' }
      ))

      span.update(output: { result: 'span completed' })
    end

    it 'updates span with metadata' do
      expect(client).to receive(:enqueue_event).with('span-update', hash_including(
        id: span.id,
        metadata: { version: '1.0', framework: 'rails' }
      ))

      span.update(metadata: { version: '1.0', framework: 'rails' })
    end
  end

  describe 'span ending' do
    it 'ends the span with output and status' do
      expect(client).to receive(:enqueue_event).with('span-update', hash_including(
        id: span.id,
        output: { result: 'success' },
        status: 'success'
      ))

      span.end(output: { result: 'success' }, status: 'success')
    end

    it 'ends the span with timing information' do
      end_time = Time.now.iso8601
      expect(client).to receive(:enqueue_event).with('span-update', hash_including(
        id: span.id,
        end_time: end_time,
        status: 'completed'
      ))

      span.end(end_time: end_time, status: 'completed')
    end
  end

  describe 'span scoring' do
    it 'creates a score for the span' do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
        name: 'span-score',
        value: 0.9,
        trace_id: trace.id,
        span_id: span.id
      ))

      span.score(name: 'span-score', value: 0.9)
    end
  end

  describe 'complex workflow' do
    it 'handles multi-level span nesting' do
      # Root span
      root_span = trace.span(name: 'root-operation')

      # First level nested span
      child_span = root_span.span(name: 'child-operation')

      # Second level nested span
      grandchild_span = child_span.span(name: 'grandchild-operation')

      # Add generation to deepest span
      generation = grandchild_span.generation(
        name: 'deep-generation',
        model: 'gpt-4',
        input: 'deep query',
        output: 'deep response'
      )

      expect(root_span.name).to eq('root-operation')
      expect(child_span.name).to eq('child-operation')
      expect(grandchild_span.name).to eq('grandchild-operation')
      expect(generation.name).to eq('deep-generation')

      # All should share the same trace_id
      expect(root_span.trace_id).to eq(trace.id)
      expect(child_span.trace_id).to eq(trace.id)
      expect(grandchild_span.trace_id).to eq(trace.id)
      expect(generation.trace_id).to eq(trace.id)
    end
  end

  describe 'span attributes' do
    it 'supports various span attributes' do
      detailed_span = trace.span(
        name: 'detailed-span',
        input: { complex: 'input' },
        metadata: {
          version: '2.0',
          environment: 'test',
          tags: %w[api service]
        },
        level: 'DEBUG'
      )

      expect(detailed_span.name).to eq('detailed-span')
      expect(detailed_span.input).to eq({ complex: 'input' })
      expect(detailed_span.trace_id).to eq(trace.id)
    end
  end
end