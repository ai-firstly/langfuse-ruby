#!/usr/bin/env ruby
# frozen_string_literal: true

# Langfuse v4 (OTLP) tracing example.
# Tracing APIs are the same as :legacy; only ingestion_mode: :otel changes the
# transport (OTLP/HTTP + x-langfuse-ingestion-version: 4).
#
#   export LANGFUSE_PUBLIC_KEY=pk-lf-...
#   export LANGFUSE_SECRET_KEY=sk-lf-...
#   export LANGFUSE_HOST=https://us.cloud.langfuse.com   # or EU / self-hosted
#   ruby examples/v4_otel_tracing.rb

require 'langfuse'

Langfuse.configure do |config|
  config.public_key = ENV.fetch('LANGFUSE_PUBLIC_KEY', nil)
  config.secret_key = ENV.fetch('LANGFUSE_SECRET_KEY', nil)
  config.host = ENV['LANGFUSE_HOST'] || ENV['LANGFUSE_BASE_URL'] || 'https://us.cloud.langfuse.com'
  config.ingestion_mode = :otel
end

puts '🚀 Langfuse v4 / OTEL tracing example'
puts "   host: #{Langfuse.client.host}"
puts "   ingestion_mode: #{Langfuse.client.ingestion_mode}"

query = 'What is Ruby?'

Langfuse.trace(
  'v4-document-qa',
  user_id: 'user-123',
  session_id: 'sess-456',
  tags: %w[v4 example],
  input: { query: query }
) do |trace|
  agent = trace.agent(name: 'qa-agent', input: { query: query })

  retrieval = agent.retriever(
    name: 'vector-search',
    input: { query: query, top_k: 3 }
  )
  docs = ['Ruby is a dynamic, object-oriented programming language.']
  retrieval.end(output: { documents: docs })

  generation = agent.generation(
    name: 'openai-completion',
    model: 'gpt-4o',
    input: [
      { role: 'system', content: 'Answer using the retrieved context only.' },
      { role: 'user', content: query }
    ],
    model_parameters: { temperature: 0.2 }
  )

  answer = 'Ruby is a dynamic, object-oriented programming language.'
  generation.end(
    output: answer,
    usage_details: { input: 48, output: 16, total: 64 },
    cost_details: { input: 0.0001, output: 0.0004, total: 0.0005 }
  )
  generation.score(name: 'faithfulness', value: 0.92, comment: 'Grounded in retrieved docs')

  agent.end(output: { answer: answer })
  trace.update(output: { answer: answer })
  trace.score(name: 'user-satisfaction', value: 0.9)

  puts "Created v4 trace: #{trace.id}"
  puts "Trace URL: #{trace.get_url}"
end

puts '✅ Flushed. Check the Langfuse UI — observations should appear in real time.'
