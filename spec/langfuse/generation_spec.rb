# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Generation do
  let(:client) { Langfuse::Client.new(public_key: 'test_key', secret_key: 'test_secret', debug: false) }
  let(:trace) { client.trace(name: 'test-trace') }
  let(:span) { trace.span(name: 'test-span') }
  let(:generation) { trace.generation(
    name: 'test-generation',
    model: 'gpt-3.5-turbo',
    input: [{ role: 'user', content: 'Hello!' }],
    output: { content: 'Hi there!' }
  ) }

  describe 'initialization' do
    it 'creates a generation with basic attributes' do
      expect(generation).to be_a(Langfuse::Generation)
      expect(generation.name).to eq('test-generation')
      expect(generation.model).to eq('gpt-3.5-turbo')
      expect(generation.input).to eq([{ role: 'user', content: 'Hello!' }])
      expect(generation.output).to eq({ content: 'Hi there!' })
      expect(generation.trace_id).to eq(trace.id)
      expect(generation.id).not_to be_nil
    end

    it 'creates a generation within a span' do
      span_generation = span.generation(
        name: 'span-generation',
        model: 'gpt-4',
        input: 'test input',
        output: 'test output'
      )

      expect(span_generation).to be_a(Langfuse::Generation)
      expect(span_generation.name).to eq('span-generation')
      expect(span_generation.model).to eq('gpt-4')
      expect(span_generation.trace_id).to eq(trace.id)
    end

    it 'creates a generation directly with trace_id' do
      direct_generation = client.generation(
        trace_id: 'test-trace-id',
        name: 'direct-generation',
        model: 'claude-3'
      )

      expect(direct_generation.trace_id).to eq('test-trace-id')
      expect(direct_generation.name).to eq('direct-generation')
    end
  end

  describe 'generation updates' do
    it 'updates generation attributes' do
      expect(client).to receive(:enqueue_event).with('generation-update', hash_including(
        id: generation.id,
        output: { content: 'Updated response' }
      ))

      generation.update(output: { content: 'Updated response' })
    end

    it 'updates generation with usage information' do
      usage_info = {
        prompt_tokens: 150,
        completion_tokens: 50,
        total_tokens: 200
      }

      expect(client).to receive(:enqueue_event).with('generation-update', hash_including(
        id: generation.id,
        usage: usage_info
      ))

      generation.update(usage: usage_info)
    end

    it 'updates generation with model parameters' do
      model_params = {
        temperature: 0.7,
        max_tokens: 1000,
        top_p: 0.9
      }

      expect(client).to receive(:enqueue_event).with('generation-update', hash_including(
        id: generation.id,
        model_parameters: model_params
      ))

      generation.update(model_parameters: model_params)
    end
  end

  describe 'generation scoring' do
    it 'creates a score for the generation' do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
        name: 'generation-score',
        value: 0.95,
        trace_id: trace.id,
        generation_id: generation.id
      ))

      generation.score(name: 'generation-score', value: 0.95)
    end

    it 'creates a score with data type and config' do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
        name: 'quality-score',
        value: 'excellent',
        data_type: 'CATEGORICAL',
        config_id: 'quality-evaluator-v1',
        trace_id: trace.id,
        generation_id: generation.id
      ))

      generation.score(
        name: 'quality-score',
        value: 'excellent',
        data_type: 'CATEGORICAL',
        config_id: 'quality-evaluator-v1'
      )
    end
  end

  describe 'complex generation workflows' do
    it 'handles chat completions with multiple messages' do
      chat_generation = trace.generation(
        name: 'chat-completion',
        model: 'gpt-4',
        input: [
          { role: 'system', content: 'You are a helpful assistant.' },
          { role: 'user', content: 'Explain Ruby programming.' },
          { role: 'assistant', content: 'Ruby is a dynamic programming language...' },
          { role: 'user', content: 'What about Ruby on Rails?' }
        ],
        output: {
          content: 'Ruby on Rails is a web application framework...',
          role: 'assistant'
        },
        usage: {
          prompt_tokens: 200,
          completion_tokens: 150,
          total_tokens: 350
        },
        model_parameters: {
          temperature: 0.7,
          max_tokens: 500,
          presence_penalty: 0.1,
          frequency_penalty: 0.1
        },
        metadata: {
          conversation_id: 'conv-123',
          user_intent: 'learning'
        }
      )

      expect(chat_generation.name).to eq('chat-completion')
      expect(chat_generation.model).to eq('gpt-4')
      expect(chat_generation.input.length).to eq(4)
      expect(chat_generation.output[:content]).to include('Ruby on Rails')
    end

    it 'handles streaming generations' do
      streaming_generation = span.generation(
        name: 'streaming-completion',
        model: 'claude-3-opus',
        input: { prompt: 'Write a poem about programming' },
        output: {
          content: 'Code flows like digital rivers...',
          role: 'assistant'
        },
        usage: {
          prompt_tokens: 10,
          completion_tokens: 50,
          total_tokens: 60
        },
        metadata: {
          streaming: true,
          finish_reason: 'stop'
        }
      )

      expect(streaming_generation.name).to eq('streaming-completion')
      expect(streaming_generation.metadata[:streaming]).to be true
    end
  end

  describe 'generation with embeddings' do
    it 'handles embedding generation' do
      embedding_generation = trace.generation(
        name: 'text-embedding',
        model: 'text-embedding-ada-002',
        input: 'The quick brown fox jumps over the lazy dog',
        output: {
          embedding: Array.new(1536) { rand(-1.0..1.0) },
          object: 'embedding'
        },
        usage: {
          prompt_tokens: 9,
          total_tokens: 9
        }
      )

      expect(embedding_generation.name).to eq('text-embedding')
      expect(embedding_generation.model).to eq('text-embedding-ada-002')
      expect(embedding_generation.output[:embedding].length).to eq(1536)
    end
  end

  describe 'generation error handling' do
    it 'handles failed generations' do
      failed_generation = trace.generation(
        name: 'failed-generation',
        model: 'gpt-3.5-turbo',
        input: 'test input',
        status: 'ERROR',
        error: {
          message: 'Rate limit exceeded',
          type: 'rate_limit_error',
          code: 'rate_limit_exceeded'
        }
      )

      expect(failed_generation.name).to eq('failed-generation')
      expect(failed_generation.status).to eq('ERROR')
    end
  end

  describe 'generation timing' do
    it 'records start and end times' do
      start_time = Time.now.iso8601
      end_time = (Time.now + 5).iso8601

      timed_generation = trace.generation(
        name: 'timed-generation',
        model: 'gpt-4',
        input: 'test',
        start_time: start_time,
        end_time: end_time,
        output: 'test output'
      )

      expect(timed_generation.name).to eq('timed-generation')
    end
  end
end