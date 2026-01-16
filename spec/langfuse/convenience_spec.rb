# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Langfuse convenience methods' do
  before do
    Langfuse.reset!
    Langfuse.configure do |config|
      config.public_key = 'test_key'
      config.secret_key = 'test_secret'
      config.host = 'https://test.langfuse.com'
      config.auto_flush = false
      config.debug = false
    end
  end

  after do
    Langfuse.reset!
  end

  describe '.client' do
    it 'returns a Client instance' do
      expect(Langfuse.client).to be_a(Langfuse::Client)
    end

    it 'returns the same client in the same thread' do
      client1 = Langfuse.client
      client2 = Langfuse.client
      expect(client1).to eq(client2)
    end

    it 'returns different clients in different threads' do
      client1 = Langfuse.client
      client2 = nil

      thread = Thread.new do
        Langfuse.configure do |config|
          config.public_key = 'test_key'
          config.secret_key = 'test_secret'
        end
        client2 = Langfuse.client
      end
      thread.join

      expect(client1).not_to eq(client2)
    end
  end

  describe '.reset!' do
    it 'clears the thread-local client' do
      client1 = Langfuse.client
      Langfuse.reset!
      client2 = Langfuse.client

      expect(client1).not_to eq(client2)
    end
  end

  describe '.trace' do
    context 'without block' do
      it 'returns a Trace instance' do
        trace = Langfuse.trace('test-trace')
        expect(trace).to be_a(Langfuse::Trace)
        expect(trace.name).to eq('test-trace')
      end

      it 'accepts all trace parameters' do
        trace = Langfuse.trace(
          'test-trace',
          user_id: 'user-123',
          session_id: 'session-456',
          input: { message: 'hello' },
          metadata: { key: 'value' }
        )

        expect(trace.user_id).to eq('user-123')
        expect(trace.session_id).to eq('session-456')
        expect(trace.input).to eq({ message: 'hello' })
        expect(trace.metadata).to eq({ key: 'value' })
      end
    end

    context 'with block' do
      it 'yields the trace to the block' do
        yielded_trace = nil

        Langfuse.trace('test-trace') do |trace|
          yielded_trace = trace
        end

        expect(yielded_trace).to be_a(Langfuse::Trace)
        expect(yielded_trace.name).to eq('test-trace')
      end

      it 'returns the block return value' do
        result = Langfuse.trace('test-trace') do |_trace|
          'block result'
        end

        expect(result).to eq('block result')
      end

      it 'calls flush after the block' do
        expect(Langfuse.client).to receive(:flush)

        Langfuse.trace('test-trace') do |_trace|
          # do nothing
        end
      end

      it 'calls flush even when block raises an error' do
        expect(Langfuse.client).to receive(:flush)

        expect do
          Langfuse.trace('test-trace') do |_trace|
            raise 'test error'
          end
        end.to raise_error('test error')
      end
    end
  end

  describe '.flush' do
    it 'calls flush on the client' do
      expect(Langfuse.client).to receive(:flush)
      Langfuse.flush
    end
  end

  describe '.shutdown' do
    it 'calls shutdown on the client' do
      expect(Langfuse.client).to receive(:shutdown)
      Langfuse.shutdown
    end
  end
end

RSpec.describe 'Langfuse null objects' do
  describe Langfuse::NullTrace do
    let(:null_trace) { Langfuse::NullTrace.new }

    it 'returns NullGeneration for generation' do
      expect(null_trace.generation(name: 'test')).to be_a(Langfuse::NullGeneration)
    end

    it 'returns NullSpan for span' do
      expect(null_trace.span(name: 'test')).to be_a(Langfuse::NullSpan)
    end

    it 'returns NullEvent for event' do
      expect(null_trace.event(name: 'test')).to be_a(Langfuse::NullEvent)
    end

    it 'returns self for update' do
      expect(null_trace.update(output: 'test')).to eq(null_trace)
    end

    it 'returns nil for score' do
      expect(null_trace.score(name: 'test', value: 0.5)).to be_nil
    end

    it 'returns nil for get_url' do
      expect(null_trace.get_url).to be_nil
    end

    it 'returns nil for id' do
      expect(null_trace.id).to be_nil
    end
  end

  describe Langfuse::NullGeneration do
    let(:null_generation) { Langfuse::NullGeneration.new }

    it 'returns self for update' do
      expect(null_generation.update(output: 'test')).to eq(null_generation)
    end

    it 'returns self for end' do
      expect(null_generation.end(output: 'test')).to eq(null_generation)
    end

    it 'returns NullSpan for span' do
      expect(null_generation.span(name: 'test')).to be_a(Langfuse::NullSpan)
    end

    it 'returns NullGeneration for generation' do
      expect(null_generation.generation(name: 'test')).to be_a(Langfuse::NullGeneration)
    end

    it 'returns nil for score' do
      expect(null_generation.score(name: 'test', value: 0.5)).to be_nil
    end
  end

  describe Langfuse::NullSpan do
    let(:null_span) { Langfuse::NullSpan.new }

    it 'returns self for update' do
      expect(null_span.update(output: 'test')).to eq(null_span)
    end

    it 'returns self for end' do
      expect(null_span.end(output: 'test')).to eq(null_span)
    end

    it 'returns NullGeneration for generation' do
      expect(null_span.generation(name: 'test')).to be_a(Langfuse::NullGeneration)
    end

    it 'returns NullSpan for span' do
      expect(null_span.span(name: 'test')).to be_a(Langfuse::NullSpan)
    end
  end
end
