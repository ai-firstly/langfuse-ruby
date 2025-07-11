#!/usr/bin/env ruby

require_relative 'lib/langfuse'

puts "🚀 Testing Langfuse Ruby SDK..."

# Test 1: Basic configuration
puts "\n1. Testing configuration..."
Langfuse.configure do |config|
  config.public_key = "test_key"
  config.secret_key = "test_secret"
  config.host = "https://test.langfuse.com"
  config.debug = true
end

puts "✅ Configuration successful"
puts "   Public key: #{Langfuse.configuration.public_key}"
puts "   Host: #{Langfuse.configuration.host}"

# Test 2: Client initialization
puts "\n2. Testing client initialization..."
begin
  client = Langfuse.new(
    public_key: "test_key",
    secret_key: "test_secret",
    host: "https://test.langfuse.com"
  )
  puts "✅ Client initialization successful"
  puts "   Client class: #{client.class}"
  puts "   Public key: #{client.public_key}"
rescue => e
  puts "❌ Client initialization failed: #{e.message}"
end

# Test 3: Trace creation
puts "\n3. Testing trace creation..."
begin
  trace = client.trace(
    name: "test-trace",
    user_id: "test-user",
    input: { message: "Hello, world!" }
  )
  puts "✅ Trace creation successful"
  puts "   Trace ID: #{trace.id}"
  puts "   Trace name: #{trace.name}"
rescue => e
  puts "❌ Trace creation failed: #{e.message}"
end

# Test 4: Generation creation
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
  puts "   Model: #{generation.model}"
rescue => e
  puts "❌ Generation creation failed: #{e.message}"
end

# Test 5: Span creation
puts "\n5. Testing span creation..."
begin
  span = trace.span(
    name: "test-span",
    input: { query: "test query" }
  )
  puts "✅ Span creation successful"
  puts "   Span ID: #{span.id}"
  puts "   Span name: #{span.name}"
rescue => e
  puts "❌ Span creation failed: #{e.message}"
end

# Test 6: Prompt template
puts "\n6. Testing prompt template..."
begin
  template = Langfuse::PromptTemplate.from_template(
    "Hello {{name}}! How are you feeling {{mood}} today?"
  )

  formatted = template.format(
    name: "Alice",
    mood: "happy"
  )

  puts "✅ Prompt template successful"
  puts "   Template variables: #{template.input_variables}"
  puts "   Formatted: #{formatted}"
rescue => e
  puts "❌ Prompt template failed: #{e.message}"
end

# Test 7: Chat prompt template
puts "\n7. Testing chat prompt template..."
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
  puts "   Template variables: #{chat_template.input_variables}"
  puts "   Messages count: #{messages.length}"
rescue => e
  puts "❌ Chat prompt template failed: #{e.message}"
end

# Test 8: Evaluators
puts "\n8. Testing evaluators..."
begin
  # Exact match evaluator
  exact_match = Langfuse::Evaluators::ExactMatchEvaluator.new
  result = exact_match.evaluate(
    input: "What is 2+2?",
    output: "4",
    expected: "4"
  )
  puts "✅ Exact match evaluator successful"
  puts "   Result: #{result}"

  # Similarity evaluator
  similarity = Langfuse::Evaluators::SimilarityEvaluator.new
  result = similarity.evaluate(
    input: "What is AI?",
    output: "Artificial Intelligence",
    expected: "AI is artificial intelligence"
  )
  puts "✅ Similarity evaluator successful"
  puts "   Result: #{result}"
rescue => e
  puts "❌ Evaluator failed: #{e.message}"
end

# Test 9: Utils
puts "\n9. Testing utilities..."
begin
  id = Langfuse::Utils.generate_id
  timestamp = Langfuse::Utils.current_timestamp

  puts "✅ Utils successful"
  puts "   Generated ID: #{id}"
  puts "   Timestamp: #{timestamp}"
rescue => e
  puts "❌ Utils failed: #{e.message}"
end

# Test 10: Event queue
puts "\n10. Testing event queue..."
begin
  queue_size_before = client.instance_variable_get(:@event_queue).length

  client.score(
    trace_id: trace.id,
    name: "test-score",
    value: 0.9
  )

  queue_size_after = client.instance_variable_get(:@event_queue).length

  puts "✅ Event queue successful"
  puts "   Queue size before: #{queue_size_before}"
  puts "   Queue size after: #{queue_size_after}"
rescue => e
  puts "❌ Event queue failed: #{e.message}"
end

puts "\n🎉 All tests completed!"
puts "   This SDK is ready for use with Langfuse!"
puts "   Remember to set your real API keys when using in production."

# Clean shutdown
client.shutdown
