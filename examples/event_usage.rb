#!/usr/bin/env ruby
# frozen_string_literal: true

require 'langfuse'

# Initialize the Langfuse client
client = Langfuse.new(
  public_key: ENV.fetch('LANGFUSE_PUBLIC_KEY', nil),
  secret_key: ENV.fetch('LANGFUSE_SECRET_KEY', nil),
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

puts '🎯 Starting event usage example...'

# Example 1: Create a trace and add events
puts "\n📝 Example 1: Creating events within a trace"

trace = client.trace(
  name: 'user-workflow',
  user_id: 'user-123',
  session_id: 'session-456',
  input: { action: 'start_workflow' }
)

puts "Created trace: #{trace.id}"

# Create a generic event
event1 = trace.event(
  name: 'user_login',
  input: { username: 'john_doe', login_method: 'oauth' },
  output: { success: true, user_id: 'user-123' },
  metadata: {
    ip_address: '192.168.1.1',
    user_agent: 'Mozilla/5.0...'
  }
)

puts "Created event: #{event1.id}"

# Create another event with custom level
event2 = trace.event(
  name: 'data_processing',
  input: { data_size: 1024, format: 'json' },
  output: { processed_records: 100, errors: 0 },
  level: 'INFO',
  metadata: {
    processing_time_ms: 250,
    memory_usage: '45MB'
  }
)

puts "Created event: #{event2.id}"

# Example 2: Creating events from spans
puts "\n🔗 Example 2: Creating events from spans"

span = trace.span(
  name: 'data-validation',
  input: { data: 'raw_data' }
)

# Create an event within the span
validation_event = span.event(
  name: 'validation_check',
  input: { rules: %w[required format length] },
  output: { valid: true, warnings: [] },
  metadata: { validation_time_ms: 15 }
)

puts "Created span event: #{validation_event.id}"

# End the span
span.end(output: { validation_result: 'passed' })

# Example 3: Creating events from generations
puts "\n🤖 Example 3: Creating events from generations"

generation = trace.generation(
  name: 'text-generation',
  model: 'gpt-3.5-turbo',
  input: [{ role: 'user', content: 'Hello, how are you?' }],
  output: { content: 'I am doing well, thank you!' },
  usage: { prompt_tokens: 12, completion_tokens: 8, total_tokens: 20 }
)

# Create an event for content filtering
filter_event = generation.event(
  name: 'content_filter',
  input: { text: 'I am doing well, thank you!' },
  output: {
    filtered: false,
    flags: [],
    confidence: 0.95
  },
  metadata: {
    filter_model: 'content-filter-v1',
    processing_time_ms: 5
  }
)

puts "Created generation event: #{filter_event.id}"

# Example 4: Error event
puts "\n❌ Example 4: Error event"

error_event = trace.event(
  name: 'error_occurred',
  input: { operation: 'database_query' },
  output: {
    error: true,
    message: 'Connection timeout',
    code: 'DB_TIMEOUT'
  },
  level: 'ERROR',
  status_message: 'Database connection failed',
  metadata: {
    retry_count: 3,
    last_attempt: Time.now.iso8601
  }
)

puts "Created error event: #{error_event.id}"

puts "Trace URL: #{trace.get_url}"

# Example 5: Direct event creation via client
puts "\n🎯 Example 5: Direct event creation via client"

direct_event = client.event(
  trace_id: trace.id,
  name: 'audit_log',
  input: { action: 'workflow_completed', user_id: 'user-123' },
  output: { logged: true, log_id: 'audit-789' },
  metadata: {
    timestamp: Time.now.iso8601,
    source: 'audit_system'
  }
)

puts "Created direct event: #{direct_event.id}"

puts "\n✅ Event usage example completed!"
puts 'Check the Langfuse dashboard to see all events in the trace.'

# Flush events to ensure they're sent
client.flush
