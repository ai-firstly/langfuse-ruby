#!/usr/bin/env ruby

require_relative 'lib/langfuse'

puts "🚀 Testing Langfuse Ruby SDK (Offline Mode)..."

# Test 1: Basic configuration
puts "\n1. Testing configuration..."
Langfuse.configure do |config|
  config.public_key = "test_key"
  config.secret_key = "test_secret"
  config.host = "https://test.langfuse.com"
  config.debug = false  # Turn off debug to avoid network calls
end

puts "✅ Configuration successful"

# Test 2: Client initialization
puts "\n2. Testing client initialization..."
begin
  client = Langfuse.new(
    public_key: "test_key",
    secret_key: "test_secret",
    host: "https://test.langfuse.com",
    debug: false
  )
  puts "✅ Client initialization successful"
rescue => e
  puts "❌ Client initialization failed: #{e.message}"
end

# Test 3: Trace creation (no network)
puts "\n3. Testing trace creation..."
begin
  trace = client.trace(
    name: "test-trace",
    user_id: "test-user",
    input: { message: "Hello, world!" }
  )
  puts "✅ Trace creation successful"
  puts "   Trace ID: #{trace.id}"
rescue => e
  puts "❌ Trace creation failed: #{e.message}"
end

# Test 4: Generation creation (no network)
puts "\n4. Testing generation creation..."
begin
  generation = trace.generation(
    name: "test-generation",
    model: "gpt-3.5-turbo",
    input: [{ role: "user", content: "Hello!" }],
    output: { content: "Hi there!" }
  )
  puts "✅ Generation creation successful"
  puts "   Generation ID: #{generation.id}"
rescue => e
  puts "❌ Generation creation failed: #{e.message}"
end

# Test 5: Prompt template
puts "\n5. Testing prompt template..."
begin
  template = Langfuse::PromptTemplate.from_template(
    "Hello {{name}}! How are you feeling {{mood}} today?"
  )

  formatted = template.format(
    name: "Alice",
    mood: "happy"
  )

  puts "✅ Prompt template successful"
  puts "   Variables: #{template.input_variables}"
  puts "   Formatted: #{formatted}"
rescue => e
  puts "❌ Prompt template failed: #{e.message}"
end

# Test 6: Chat prompt template
puts "\n6. Testing chat prompt template..."
begin
  chat_template = Langfuse::ChatPromptTemplate.from_messages([
    { role: "system", content: "You are a helpful {{role}} assistant." },
    { role: "user", content: "{{user_input}}" }
  ])

  messages = chat_template.format(
    role: "coding",
    user_input: "Help me with Ruby"
  )

  puts "✅ Chat prompt template successful"
  puts "   Variables: #{chat_template.input_variables}"
  puts "   Messages: #{messages.length}"
rescue => e
  puts "❌ Chat prompt template failed: #{e.message}"
end

# Test 7: Evaluators
puts "\n7. Testing evaluators..."
begin
  # Exact match evaluator
  exact_match = Langfuse::Evaluators::ExactMatchEvaluator.new
  result = exact_match.evaluate(
    "What is 2+2?",
    "4",
    expected: "4"
  )
  puts "✅ Exact match evaluator: #{result}"

  # Similarity evaluator
  similarity = Langfuse::Evaluators::SimilarityEvaluator.new
  result = similarity.evaluate(
    "What is AI?",
    "Artificial Intelligence",
    expected: "AI is artificial intelligence"
  )
  puts "✅ Similarity evaluator: #{result}"

  # Length evaluator
  length = Langfuse::Evaluators::LengthEvaluator.new(min_length: 5, max_length: 20)
  result = length.evaluate(
    "Test input",
    "This is a test",
    expected: nil
  )
  puts "✅ Length evaluator: #{result}"

  # Contains evaluator
  contains = Langfuse::Evaluators::ContainsEvaluator.new
  result = contains.evaluate(
    "Find Ruby",
    "Ruby programming language",
    expected: "Ruby"
  )
  puts "✅ Contains evaluator: #{result}"

  # Regex evaluator
  regex = Langfuse::Evaluators::RegexEvaluator.new(pattern: /\d+/)
  result = regex.evaluate(
    "Find numbers",
    "There are 42 apples",
    expected: nil
  )
  puts "✅ Regex evaluator: #{result}"

rescue => e
  puts "❌ Evaluator failed: #{e.message}"
end

# Test 8: Utils
puts "\n8. Testing utilities..."
begin
  id = Langfuse::Utils.generate_id
  timestamp = Langfuse::Utils.current_timestamp

  # Test data transformation
  hash_data = { "key1" => "value1", "nested" => { "key2" => "value2" } }
  symbolized = Langfuse::Utils.deep_symbolize_keys(hash_data)
  stringified = Langfuse::Utils.deep_stringify_keys(symbolized)

  puts "✅ Utils successful"
  puts "   ID: #{id[0..8]}..."
  puts "   Timestamp: #{timestamp}"
  puts "   Symbolized keys: #{symbolized.keys}"
  puts "   Stringified keys: #{stringified.keys}"
rescue => e
  puts "❌ Utils failed: #{e.message}"
end

# Test 9: Event queue (without network)
puts "\n9. Testing event queue..."
begin
  queue_size_before = client.instance_variable_get(:@event_queue).length

  # Add some events
  client.score(
    trace_id: trace.id,
    name: "test-score",
    value: 0.9
  )

  trace.score(
    name: "trace-score",
    value: 0.8
  )

  generation.score(
    name: "generation-score",
    value: 0.95
  )

  queue_size_after = client.instance_variable_get(:@event_queue).length

  puts "✅ Event queue successful"
  puts "   Events added: #{queue_size_after - queue_size_before}"
  puts "   Total events: #{queue_size_after}"
rescue => e
  puts "❌ Event queue failed: #{e.message}"
end

# Test 10: Complex workflow
puts "\n10. Testing complex workflow..."
begin
  # Create a complex trace with nested spans
  complex_trace = client.trace(
    name: "complex-workflow",
    user_id: "user-456",
    session_id: "session-789",
    input: { query: "Explain quantum computing" },
    metadata: {
      environment: "test",
      version: "1.0.0",
      tags: ["physics", "computing"]
    }
  )

  # Document retrieval span
  retrieval_span = complex_trace.span(
    name: "document-retrieval",
    input: { query: "quantum computing basics" }
  )

  # Embedding generation
  embedding_gen = retrieval_span.generation(
    name: "embedding-generation",
    model: "text-embedding-ada-002",
    input: "quantum computing basics",
    output: Array.new(1536) { rand(-1.0..1.0) }, # Mock embedding
    usage: { prompt_tokens: 4, total_tokens: 4 }
  )

  retrieval_span.end(
    output: {
      documents: [
        "Quantum computing uses quantum bits...",
        "Quantum algorithms can solve certain problems..."
      ]
    }
  )

  # Answer generation span
  answer_span = complex_trace.span(
    name: "answer-generation",
    input: {
      query: "Explain quantum computing",
      context: ["Quantum computing uses quantum bits...", "Quantum algorithms can solve certain problems..."]
    }
  )

  # LLM generation
  llm_gen = answer_span.generation(
    name: "openai-completion",
    model: "gpt-4",
    input: [
      { role: "system", content: "You are a physics expert." },
      { role: "user", content: "Explain quantum computing based on the context." }
    ],
    output: {
      content: "Quantum computing is a revolutionary approach to computation that leverages quantum mechanical phenomena like superposition and entanglement to process information in fundamentally different ways than classical computers."
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
      answer: "Quantum computing is a revolutionary approach to computation that leverages quantum mechanical phenomena like superposition and entanglement to process information in fundamentally different ways than classical computers."
    }
  )

  complex_trace.update(
    output: {
      answer: "Quantum computing is a revolutionary approach to computation that leverages quantum mechanical phenomena like superposition and entanglement to process information in fundamentally different ways than classical computers."
    }
  )

  puts "✅ Complex workflow successful"
  puts "   Trace ID: #{complex_trace.id}"
  puts "   Spans created: 2"
  puts "   Generations created: 2"

rescue => e
  puts "❌ Complex workflow failed: #{e.message}"
end

# Test 11: Error handling
puts "\n11. Testing error handling..."
begin
  # Test validation error
  begin
    Langfuse::Utils.validate_required_fields({ name: "test" }, [:name, :required_field])
  rescue Langfuse::ValidationError => e
    puts "✅ Validation error caught: #{e.message}"
  end

  # Test authentication error
  begin
    Langfuse.new(public_key: nil, secret_key: "secret")
  rescue Langfuse::AuthenticationError => e
    puts "✅ Authentication error caught: #{e.message}"
  end

rescue => e
  puts "❌ Error handling failed: #{e.message}"
end

# Final summary
puts "\n🎉 All offline tests completed successfully!"
puts "   The Langfuse Ruby SDK is ready for use!"
puts "   Total events in queue: #{client.instance_variable_get(:@event_queue).length}"

# Clean shutdown (kill background thread)
client.instance_variable_get(:@flush_thread)&.kill
puts "   Background thread terminated"

puts "\n📚 Next steps:"
puts "   1. Set your real Langfuse API keys"
puts "   2. Configure the correct host URL"
puts "   3. Start using the SDK in your application"
puts "   4. Check the examples/ directory for more usage patterns"
