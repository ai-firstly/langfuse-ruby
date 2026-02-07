#!/usr/bin/env ruby
# frozen_string_literal: true

require 'langfuse'

# Configure Langfuse globally
Langfuse.configure do |config|
  config.public_key = ENV.fetch('LANGFUSE_PUBLIC_KEY', nil)
  config.secret_key = ENV.fetch('LANGFUSE_SECRET_KEY', nil)
  config.host = ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
end

puts '🚀 Simplified usage example...'

# Example 1: Block-based tracing with automatic flush
puts "\n📝 Example 1: Block-based tracing (recommended)"

result = Langfuse.trace('simplified-chat', user_id: 'user-123', input: { message: 'Hello!' }) do |trace|
  # Create a generation for the LLM call
  generation = trace.generation(
    name: 'openai-chat',
    model: 'gpt-4',
    input: [{ role: 'user', content: 'Hello!' }],
    model_parameters: { temperature: 0.7 }
  )

  # Simulate LLM response
  response_content = "Hi there! How can I help you today?"
  usage = { prompt_tokens: 10, completion_tokens: 15, total_tokens: 25 }

  # End the generation with output and usage
  generation.end(output: response_content, usage: usage)

  # Update trace with final output
  trace.update(output: response_content)

  # Return value from block
  response_content
end
# Flush happens automatically here!

puts "Response: #{result}"

# Example 2: Nested spans with block-based tracing
puts "\n🔗 Example 2: Complex workflow with spans"

Langfuse.trace('document-qa', user_id: 'user-456') do |trace|
  # Retrieval span
  retrieval = trace.span(name: 'document-retrieval', input: { query: 'What is Ruby?' })
  
  # Simulate embedding generation
  retrieval.generation(
    name: 'embedding',
    model: 'text-embedding-ada-002',
    input: 'What is Ruby?',
    output: [0.1, 0.2, 0.3],
    usage: { prompt_tokens: 5, total_tokens: 5 }
  )
  
  retrieval.end(output: { documents: ['Ruby is a programming language...'] })

  # Answer generation span
  answer_span = trace.span(name: 'answer-generation')
  
  gen = answer_span.generation(
    name: 'openai-completion',
    model: 'gpt-4',
    input: [{ role: 'user', content: 'What is Ruby?' }]
  )
  
  gen.end(
    output: 'Ruby is a dynamic, object-oriented programming language.',
    usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 }
  )
  
  answer_span.end(output: { answer: 'Ruby is a dynamic programming language.' })
  
  # Score the trace
  trace.score(name: 'relevance', value: 0.95, comment: 'Highly relevant answer')
end

# Example 3: Direct trace without block (manual flush required)
puts "\n📌 Example 3: Direct trace usage"

trace = Langfuse.trace('manual-trace', user_id: 'user-789')
puts "Created trace: #{trace.id}"

generation = trace.generation(
  name: 'quick-generation',
  model: 'gpt-3.5-turbo',
  input: 'Quick test'
)
generation.end(output: 'Done!')

# Manual flush required when not using block
Langfuse.flush

# Example 4: Get and compile prompts
puts "\n📋 Example 4: Prompt management"

# Get a prompt (would fail gracefully with nil if not configured)
# prompt = Langfuse.get_prompt('my-prompt', variables: { name: 'World' })
# puts "Compiled prompt: #{prompt}"

# Graceful degradation example
puts "Testing graceful degradation with invalid config..."
Langfuse.reset!
Langfuse.configure do |config|
  config.public_key = nil
  config.secret_key = nil
end

# This will use NullTrace when client creation fails
# The block still executes, just without actual tracing
begin
  Langfuse.trace('will-fail') do |trace|
    puts "Trace type: #{trace.class}"
    gen = trace.generation(name: 'test', model: 'gpt-4', input: 'hello')
    puts "Generation type: #{gen.class}"
    gen.end(output: 'world')
  end
rescue => e
  puts "Handled error: #{e.message}"
end

puts "\n✅ Simplified usage example completed!"
