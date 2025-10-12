# frozen_string_literal: true

# Helper module for offline testing
module OfflineModeHelper
  def create_offline_client(options = {})
    default_options = {
      public_key: 'test_key',
      secret_key: 'test_secret',
      host: 'https://test.langfuse.com',
      debug: false,
      auto_flush: false  # Disable auto_flush for controlled testing
    }

    Langfuse::Client.new(default_options.merge(options))
  end

  def create_complex_trace(client)
    client.trace(
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
  end

  def build_complex_workflow(trace)
    # Document retrieval span
    retrieval_span = trace.span(
      name: 'document-retrieval',
      input: { query: 'quantum computing basics' }
    )

    # Embedding generation
    retrieval_span.generation(
      name: 'embedding-generation',
      model: 'text-embedding-ada-002',
      input: 'quantum computing basics',
      output: Array.new(1536) { rand(-1.0..1.0) }, # Mock embedding
      usage: { prompt_tokens: 4, total_tokens: 4 }
    )

    retrieval_span.end(
      output: {
        documents: [
          'Quantum computing uses quantum bits...',
          'Quantum algorithms can solve certain problems...'
        ]
      }
    )

    # Answer generation span
    answer_span = trace.span(
      name: 'answer-generation',
      input: {
        query: 'Explain quantum computing',
        context: ['Quantum computing uses quantum bits...', 'Quantum algorithms can solve certain problems...']
      }
    )

    # LLM generation
    answer_span.generation(
      name: 'openai-completion',
      model: 'gpt-4',
      input: [
        { role: 'system', content: 'You are a physics expert.' },
        { role: 'user', content: 'Explain quantum computing based on the context.' }
      ],
      output: {
        content: 'Quantum computing is a revolutionary approach to computation that leverages ' \
                 'quantum mechanical phenomena like superposition and entanglement to process ' \
                 'information in fundamentally different ways than classical computers.'
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

    answer_span.end(
      output: {
        answer: 'Quantum computing is a revolutionary approach to computation that leverages ' \
                'quantum mechanical phenomena like superposition and entanglement to process ' \
                'information in fundamentally different ways than classical computers.'
      }
    )

    trace
  end

  def create_test_events(client, count = 5)
    events = []
    count.times do |i|
      trace = client.trace(name: "test-trace-#{i}")
      span = trace.span(name: "test-span-#{i}")
      generation = span.generation(
        name: "test-generation-#{i}",
        model: 'test-model',
        input: "test input #{i}",
        output: "test output #{i}"
      )
      events << { trace:, span:, generation: }
    end
    events
  end

  def queue_size(client)
    client.instance_variable_get(:@event_queue).length
  end

  def get_queued_events(client)
    client.instance_variable_get(:@event_queue).dup
  end

  def mock_successful_flush(client)
    allow(client).to receive(:post).and_return({ success: true })
  end

  def cleanup_client(client)
    client.shutdown if client
  end
end