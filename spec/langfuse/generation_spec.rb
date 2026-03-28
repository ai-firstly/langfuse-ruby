# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Generation do
  let(:client) do
    Langfuse::Client.new(
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com',
      auto_flush: false
    )
  end

  describe '#initialize' do
    it 'creates a generation with all params' do
      generation = client.generation(
        trace_id: 'trace-1',
        id: 'gen-1',
        name: 'test-gen',
        start_time: '2026-01-01T00:00:00Z',
        end_time: '2026-01-01T00:01:00Z',
        completion_start_time: '2026-01-01T00:00:30Z',
        model: 'gpt-4',
        model_parameters: { temperature: 0.7 },
        input: [{ role: 'user', content: 'Hello' }],
        output: 'Hi there',
        usage: { prompt_tokens: 10, completion_tokens: 5 },
        metadata: { env: 'test' },
        level: 'DEBUG',
        status_message: 'ok',
        parent_observation_id: 'parent-1',
        version: '1.0'
      )

      expect(generation).to be_a(Langfuse::Generation)
      expect(generation.id).to eq('gen-1')
      expect(generation.trace_id).to eq('trace-1')
      expect(generation.name).to eq('test-gen')
      expect(generation.start_time).to eq('2026-01-01T00:00:00Z')
      expect(generation.end_time).to eq('2026-01-01T00:01:00Z')
      expect(generation.completion_start_time).to eq('2026-01-01T00:00:30Z')
      expect(generation.model).to eq('gpt-4')
      expect(generation.model_parameters).to eq({ temperature: 0.7 })
      expect(generation.input).to eq([{ role: 'user', content: 'Hello' }])
      expect(generation.output).to eq('Hi there')
      expect(generation.usage).to eq({ prompt_tokens: 10, completion_tokens: 5 })
      expect(generation.metadata).to eq({ env: 'test' })
      expect(generation.level).to eq('DEBUG')
      expect(generation.status_message).to eq('ok')
      expect(generation.parent_observation_id).to eq('parent-1')
      expect(generation.version).to eq('1.0')
    end

    it 'enqueues a generation-create event' do
      expect(client).to receive(:enqueue_event).with('generation-create', hash_including(
                                                                            trace_id: 'trace-1',
                                                                            name: 'test-gen',
                                                                            model: 'gpt-4'
                                                                          ))

      client.generation(trace_id: 'trace-1', name: 'test-gen', model: 'gpt-4')
    end

    it 'generates an id when not provided' do
      generation = client.generation(trace_id: 'trace-1')

      expect(generation.id).not_to be_nil
      expect(generation.id).not_to be_empty
    end

    it 'defaults model_parameters, usage, and metadata to empty hashes' do
      generation = client.generation(trace_id: 'trace-1')

      expect(generation.model_parameters).to eq({})
      expect(generation.usage).to eq({})
      expect(generation.metadata).to eq({})
    end
  end

  describe '#update' do
    let(:generation) { client.generation(trace_id: 'trace-1', name: 'original', model: 'gpt-3.5-turbo') }

    it 'updates fields' do
      generation.update(
        name: 'updated',
        model: 'gpt-4',
        output: 'response text',
        usage: { prompt_tokens: 20 },
        metadata: { key: 'value' },
        level: 'WARNING',
        status_message: 'completed',
        version: '2.0',
        completion_start_time: '2026-01-01T00:00:30Z',
        end_time: '2026-01-01T00:01:00Z'
      )

      expect(generation.name).to eq('updated')
      expect(generation.model).to eq('gpt-4')
      expect(generation.output).to eq('response text')
      expect(generation.usage).to eq({ prompt_tokens: 20 })
      expect(generation.metadata).to eq({ key: 'value' })
      expect(generation.level).to eq('WARNING')
      expect(generation.status_message).to eq('completed')
      expect(generation.version).to eq('2.0')
      expect(generation.completion_start_time).to eq('2026-01-01T00:00:30Z')
      expect(generation.end_time).to eq('2026-01-01T00:01:00Z')
    end

    it 'merges model_parameters' do
      generation = client.generation(
        trace_id: 'trace-1',
        model_parameters: { temperature: 0.7 }
      )

      generation.update(model_parameters: { max_tokens: 100 })

      expect(generation.model_parameters).to eq({ temperature: 0.7, max_tokens: 100 })
    end

    it 'enqueues a generation-update event' do
      expect(client).to receive(:enqueue_event).with('generation-create', anything)
      expect(client).to receive(:enqueue_event).with('generation-update', hash_including(
                                                                            trace_id: 'trace-1',
                                                                            name: 'updated'
                                                                          ))

      generation.update(name: 'updated')
    end

    it 'returns self for chaining' do
      result = generation.update(name: 'updated')

      expect(result).to eq(generation)
    end
  end

  describe '#end' do
    let(:generation) { client.generation(trace_id: 'trace-1', name: 'test-gen', model: 'gpt-4') }

    it 'sets end_time to current time by default' do
      allow(Langfuse::Utils).to receive(:current_timestamp).and_return('2026-01-01T00:01:00Z')

      generation.end

      expect(generation.end_time).to eq('2026-01-01T00:01:00Z')
    end

    it 'sets end_time to provided value' do
      generation.end(end_time: '2026-01-01T00:05:00Z')

      expect(generation.end_time).to eq('2026-01-01T00:05:00Z')
    end

    it 'sets output and usage' do
      generation.end(output: 'final response', usage: { prompt_tokens: 10, completion_tokens: 5 })

      expect(generation.output).to eq('final response')
      expect(generation.usage).to eq({ prompt_tokens: 10, completion_tokens: 5 })
    end

    it 'enqueues a generation-update event' do
      expect(client).to receive(:enqueue_event).with('generation-create', anything)
      expect(client).to receive(:enqueue_event).with('generation-update', hash_including(
                                                                            trace_id: 'trace-1'
                                                                          ))

      generation.end
    end

    it 'returns self for chaining' do
      result = generation.end

      expect(result).to eq(generation)
    end
  end

  describe '#span' do
    let(:generation) { client.generation(trace_id: 'trace-1', name: 'parent-gen', model: 'gpt-4') }

    it 'creates a child span with parent_observation_id set to generation id' do
      child_span = generation.span(name: 'child-span')

      expect(child_span).to be_a(Langfuse::Span)
      expect(child_span.parent_observation_id).to eq(generation.id)
      expect(child_span.trace_id).to eq('trace-1')
      expect(child_span.name).to eq('child-span')
    end
  end

  describe '#generation' do
    let(:generation) { client.generation(trace_id: 'trace-1', name: 'parent-gen', model: 'gpt-4') }

    it 'creates a child generation with parent_observation_id' do
      child_gen = generation.generation(name: 'child-gen', model: 'gpt-3.5-turbo')

      expect(child_gen).to be_a(Langfuse::Generation)
      expect(child_gen.parent_observation_id).to eq(generation.id)
      expect(child_gen.trace_id).to eq('trace-1')
      expect(child_gen.name).to eq('child-gen')
      expect(child_gen.model).to eq('gpt-3.5-turbo')
    end
  end

  describe '#event' do
    let(:generation) { client.generation(trace_id: 'trace-1', name: 'parent-gen', model: 'gpt-4') }

    it 'creates a child event with parent_observation_id' do
      child_event = generation.event(name: 'child-event')

      expect(child_event).to be_a(Langfuse::Event)
      expect(child_event.parent_observation_id).to eq(generation.id)
      expect(child_event.trace_id).to eq('trace-1')
      expect(child_event.name).to eq('child-event')
    end
  end

  describe 'enhanced observation type methods' do
    let(:generation) { client.generation(trace_id: 'trace-1', name: 'parent-gen', model: 'gpt-4') }

    %w[agent tool chain retriever evaluator guardrail].each do |type|
      describe "##{type}" do
        it "creates a span with as_type '#{type}' and parent_observation_id" do
          child = generation.send(type, name: "child-#{type}")

          expect(child).to be_a(Langfuse::Span)
          expect(child.as_type).to eq(type)
          expect(child.parent_observation_id).to eq(generation.id)
          expect(child.trace_id).to eq('trace-1')
          expect(child.name).to eq("child-#{type}")
        end
      end
    end

    describe '#embedding' do
      it "creates a span with as_type 'embedding' and parent_observation_id" do
        child = generation.embedding(name: 'child-embedding', model: 'text-embedding-ada-002', usage: { prompt_tokens: 5 })

        expect(child).to be_a(Langfuse::Span)
        expect(child.as_type).to eq('embedding')
        expect(child.parent_observation_id).to eq(generation.id)
        expect(child.trace_id).to eq('trace-1')
        expect(child.name).to eq('child-embedding')
        expect(child.metadata[:model]).to eq('text-embedding-ada-002')
        expect(child.metadata[:usage]).to eq({ prompt_tokens: 5 })
      end
    end
  end

  describe '#score' do
    let(:generation) { client.generation(trace_id: 'trace-1', name: 'test-gen', model: 'gpt-4') }

    it 'calls client.score with observation_id' do
      expect(client).to receive(:score).with(
        observation_id: generation.id,
        name: 'accuracy',
        value: 0.95,
        data_type: nil,
        comment: 'good'
      )

      generation.score(name: 'accuracy', value: 0.95, comment: 'good')
    end
  end

  describe '#get_url' do
    it 'returns correct URL format' do
      generation = client.generation(trace_id: 'trace-1', id: 'gen-1', model: 'gpt-4')

      expect(generation.get_url).to eq('https://test.langfuse.com/trace/trace-1?observation=gen-1')
    end
  end

  describe '#to_dict' do
    it 'returns hash with all fields' do
      generation = client.generation(
        trace_id: 'trace-1',
        id: 'gen-1',
        name: 'test-gen',
        model: 'gpt-4',
        model_parameters: { temperature: 0.7 },
        input: 'hello',
        output: 'hi',
        usage: { prompt_tokens: 10 },
        metadata: { env: 'test' },
        level: 'DEBUG',
        status_message: 'ok',
        parent_observation_id: 'parent-1',
        version: '1.0'
      )

      dict = generation.to_dict

      expect(dict[:id]).to eq('gen-1')
      expect(dict[:trace_id]).to eq('trace-1')
      expect(dict[:name]).to eq('test-gen')
      expect(dict[:model]).to eq('gpt-4')
      expect(dict[:model_parameters]).to eq({ temperature: 0.7 })
      expect(dict[:input]).to eq('hello')
      expect(dict[:output]).to eq('hi')
      expect(dict[:usage]).to eq({ prompt_tokens: 10 })
      expect(dict[:metadata]).to eq({ env: 'test' })
      expect(dict[:level]).to eq('DEBUG')
      expect(dict[:status_message]).to eq('ok')
      expect(dict[:parent_observation_id]).to eq('parent-1')
      expect(dict[:version]).to eq('1.0')
    end

    it 'includes :type when as_type is set' do
      generation = client.generation(
        trace_id: 'trace-1',
        id: 'gen-1',
        model: 'gpt-4',
        as_type: 'generation'
      )

      dict = generation.to_dict

      expect(dict[:type]).to eq('generation')
    end

    it 'does not include :type when as_type is nil' do
      generation = client.generation(
        trace_id: 'trace-1',
        id: 'gen-1',
        model: 'gpt-4'
      )

      dict = generation.to_dict

      expect(dict).not_to have_key(:type)
    end
  end

  describe '#validate_as_type' do
    it 'returns nil for nil input' do
      generation = client.generation(trace_id: 'trace-1', as_type: nil)

      expect(generation.as_type).to be_nil
    end

    it 'returns string for valid type' do
      generation = client.generation(trace_id: 'trace-1', as_type: 'generation')

      expect(generation.as_type).to eq('generation')
    end

    it 'raises ValidationError for invalid type' do
      expect do
        client.generation(trace_id: 'trace-1', as_type: 'invalid_type')
      end.to raise_error(Langfuse::ValidationError, /Invalid observation type/)
    end
  end
end
