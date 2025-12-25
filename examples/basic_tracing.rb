#!/usr/bin/env ruby
# frozen_string_literal: true

require 'langfuse'

# Initialize the Langfuse client
client = Langfuse.new(
  public_key: ENV.fetch('LANGFUSE_PUBLIC_KEY', nil),
  secret_key: ENV.fetch('LANGFUSE_SECRET_KEY', nil),
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

puts '🚀 Starting basic tracing example...'

# Example 1: Simple trace with generation
puts "\n📝 Example 1: Simple trace with generation"

trace = client.trace(
  name: 'simple-chat',
  user_id: 'user-123',
  session_id: 'session-456',
  input: { message: 'Hello, how are you?' },
  environment: 'development',
  metadata: {
    version: '1.0.0'
  }
)

puts "Created trace: #{trace.id}"

generation = trace.generation(
  name: 'openai-chat',
  model: 'gpt-3.5-turbo',
  input: [
    { role: 'user', content: 'Hello, how are you?' }
  ],
  output: { content: "I'm doing well, thank you! How can I help you today?" },
  usage: {
    prompt_tokens: 12,
    completion_tokens: 18,
    total_tokens: 30
  },
  model_parameters: {
    temperature: 0.7,
    max_tokens: 150
  }
)

puts "Created generation: #{generation.id}"

puts "Trace URL: #{trace.get_url}"

# Example 2: Nested spans for complex workflow
puts "\n🔗 Example 2: Nested spans for complex workflow"

workflow_trace = client.trace(
  name: 'document-qa-workflow',
  user_id: 'user-456',
  input: { question: 'What is machine learning?' }
)

# Document retrieval span
retrieval_span = workflow_trace.span(
  name: 'document-retrieval',
  input: { query: 'What is machine learning?' }
)

# Embedding generation within retrieval
retrieval_span.generation(
  name: 'embedding-generation',
  model: 'text-embedding-ada-002',
  input: 'What is machine learning?',
  output: [0.1, 0.2, 0.3, 0.4, 0.5], # Simplified embedding
  usage: { prompt_tokens: 5, total_tokens: 5 }
)

# End retrieval span
retrieval_span.end(
  output: {
    documents: [
      'Machine learning is a subset of artificial intelligence...',
      'ML algorithms learn patterns from data...'
    ]
  }
)

# Answer generation span
answer_span = workflow_trace.span(
  name: 'answer-generation',
  input: {
    question: 'What is machine learning?',
    context: [
      'Machine learning is a subset of artificial intelligence...',
      'ML algorithms learn patterns from data...'
    ]
  }
)

# LLM generation for answer
answer_gen = answer_span.generation(
  name: 'openai-completion',
  model: 'gpt-3.5-turbo',
  input: [
    {
      role: 'system',
      content: "Answer the user's question based on the provided context."
    },
    {
      role: 'user',
      content: 'What is machine learning? Context: Machine learning is a subset of artificial ' \
               'intelligence... ML algorithms learn patterns from data...'
    }
  ],
  output: {
    content: 'Machine learning is a subset of artificial intelligence that enables computers to learn ' \
             'and improve from experience without being explicitly programmed. ML algorithms identify ' \
             'patterns in data and use these patterns to make predictions or decisions.'
  },
  usage: {
    prompt_tokens: 85,
    completion_tokens: 45,
    total_tokens: 130
  }
)

answer_span.end(
  output: {
    answer: 'Machine learning is a subset of artificial intelligence that enables computers to learn ' \
            'and improve from experience without being explicitly programmed. ML algorithms identify ' \
            'patterns in data and use these patterns to make predictions or decisions.'
  }
)

puts "Workflow trace URL: #{workflow_trace.get_url}"

# Example 3: Adding scores and evaluations
puts "\n⭐ Example 3: Adding scores and evaluations"

# Score the generation quality
answer_gen.score(
  name: 'accuracy',
  value: 0.9,
  comment: 'Highly accurate answer based on context'
)

answer_gen.score(
  name: 'helpfulness',
  value: 0.85,
  comment: 'Very helpful and informative response'
)

# Score the entire workflow
workflow_trace.score(
  name: 'user-satisfaction',
  value: 0.95,
  comment: 'User was very satisfied with the answer'
)

puts 'Added scores to generation and trace'

# Example 4: Error handling
puts "\n🚨 Example 4: Error handling"

begin
  error_trace = client.trace(name: 'error-example')

  error_trace.generation(
    name: 'failed-generation',
    model: 'gpt-3.5-turbo',
    input: [{ role: 'user', content: 'This will fail' }],
    level: 'ERROR',
    status_message: 'Rate limit exceeded'
  )

  puts "Created error trace: #{error_trace.id}"
rescue Langfuse::RateLimitError => e
  puts "Rate limit error: #{e.message}"
rescue Langfuse::APIError => e
  puts "API error: #{e.message}"
end

# Flush all events
puts "\n🔄 Flushing events..."
client.flush

puts "\n✅ Basic tracing example completed!"
puts 'Check your Langfuse dashboard to see the traces.'

# Shutdown client
client.shutdown
