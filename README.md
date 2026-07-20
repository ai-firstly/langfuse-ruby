# Langfuse Ruby SDK

[![Gem Version](https://badge.fury.io/rb/langfuse-ruby.svg)](https://badge.fury.io/rb/langfuse-ruby) [![CI](https://github.com/ai-firstly/langfuse-ruby/workflows/CI/badge.svg)](https://github.com/ai-firstly/langfuse-ruby/actions/workflows/ci.yml) [![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1.0-red.svg)](https://www.ruby-lang.org/) [![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Ruby SDK for [Langfuse](https://langfuse.com) - the open-source LLM engineering platform. This SDK provides comprehensive tracing, prompt management, and evaluation capabilities for LLM applications.

## Features

- 🔍 **Tracing**: Complete observability for LLM applications with traces, spans, and generations
- 📝 **Prompt Management**: Version control and deployment of prompts with caching
- 📊 **Evaluation**: Built-in evaluators and custom scoring capabilities
- 🎯 **Events**: Generic event tracking for custom application events and logging
- 🚀 **Async Processing**: Background event processing with automatic batching
- 🔒 **Type Safety**: Comprehensive error handling and validation
- 🎯 **Framework Integration**: Easy integration with popular Ruby frameworks

## Installation

This gem requires Ruby >= 3.1 and is tested against Ruby 3.1–4.0. For
development, Ruby version is managed with [mise](https://mise.jdx.dev) (defaults
to the latest stable Ruby via `.mise.toml`).

Add this line to your application's Gemfile:

```ruby
gem 'langfuse-ruby'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install langfuse-ruby
```

### Development setup with mise

```bash
# Install mise (if not already installed), then trust the project config and
# install the pinned Ruby version.
brew install mise                  # macOS; see mise docs for other OSes
mise install                       # installs Ruby from .mise.toml
bundle install                     # install gem dependencies
bundle exec rake spec              # run the test suite
```

## Quick Start

### 1. Initialize the Client

```ruby
require 'langfuse'

# Initialize with API keys
client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  host: "https://cloud.langfuse.com"  # Optional, defaults to cloud.langfuse.com
)

# Or configure globally
Langfuse.configure do |config|
  config.public_key = "pk-lf-..."
  config.secret_key = "sk-lf-..."
  config.host = "https://cloud.langfuse.com"
end

client = Langfuse.new
```

### OpenTelemetry (OTEL) Ingestion Mode

Langfuse v4 introduces a faster data model powered by OpenTelemetry. To use
it, enable the OTEL ingestion mode. This sends data via the OTLP/HTTP JSON
endpoint (`/api/public/otel/v1/traces`) with the `x-langfuse-ingestion-version: 4`
header for real-time ingestion and observation-level online evaluators.

```ruby
# Via constructor
client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  ingestion_mode: :otel
)

# Via global configuration
Langfuse.configure do |config|
  config.public_key = "pk-lf-..."
  config.secret_key = "sk-lf-..."
  config.ingestion_mode = :otel
end

# Via environment variable
# LANGFUSE_INGESTION_MODE=otel
```

All existing tracing APIs work unchanged. The SDK maps Langfuse events to
OpenTelemetry spans with the appropriate `langfuse.*` and `gen_ai.*` attributes.
No additional dependencies are required.

**Scores in OTel mode:** scores are not part of the OTLP trace mapping. The SDK
always sends them through the ingestion API (`/api/public/ingestion`) as
`score-create` events, and normalizes `trace_id` / `observation_id` to W3C hex
IDs so they attach to the correct OTel-ingested entities. If an OTEL export
fails mid-batch, both the OTEL events and any scores from that batch are
re-queued for retry.

```ruby
# Scores work the same in both modes
client = Langfuse.new(ingestion_mode: :otel, ...)
trace = client.trace(name: "chat")
generation = trace.generation(name: "llm", model: "gpt-4o")
generation.score(name: "faithfulness", value: 0.9)
client.flush  # traces/spans → OTLP; scores → ingestion API
```

### 2. Basic Tracing

```ruby
# Create a trace
trace = client.trace(
  name: "chat-completion",
  user_id: "user123",
  session_id: "session456",
  environment: "production"
)

# Add a generation (LLM call)
generation = trace.generation(
  name: "openai-completion",
  model: "gpt-3.5-turbo",
  input: [{ role: "user", content: "Hello, world!" }],
  model_parameters: { temperature: 0.7, max_tokens: 100 }
)

generation.end(output: 'Hello! How can I help you today?', usage: { prompt_tokens: 10, completion_tokens: 15, total_tokens: 25 })

trace.update(output: 'Hello! How can I help you today?')

# Flush events (optional - happens automatically)
client.flush
```

## Simplified Usage (Recommended)

For most use cases, you can use the simplified class-level API with automatic flush:

### Block-based Tracing

```ruby
require 'langfuse'

# Configure once
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
end

# Use block-based tracing - flush happens automatically!
Langfuse.trace("my-trace", user_id: "user-1", input: { message: "Hello" }) do |trace|
  generation = trace.generation(
    name: "openai-chat",
    model: "gpt-4",
    input: [{ role: "user", content: "Hello" }],
    model_parameters: { temperature: 0.7 }
  )

  # Call your LLM
  response = call_openai(...)

  # Record the response
  generation.end(output: response.content, usage: response.usage)
  trace.update(output: response.content)
end  # Automatic flush here!
```

### Get Prompts with Variables

```ruby
# Get and compile a prompt in one call
prompt = Langfuse.get_prompt("greeting-prompt", variables: { name: "Alice" })
# => "Hello Alice! How can I help you today?"

# Get prompt without compilation
prompt_obj = Langfuse.get_prompt("greeting-prompt")
compiled = prompt_obj.compile(name: "Bob")
```

### Graceful Degradation

The simplified API includes null objects that ensure your code continues working even if Langfuse is unavailable:

```ruby
# If Langfuse fails, a NullTrace is used - your code still runs
Langfuse.trace("my-trace") do |trace|
  # This works even if Langfuse is down
  gen = trace.generation(name: "test", model: "gpt-4", input: "hello")
  gen.end(output: "world")
end
```

### Other Class Methods

```ruby
# Get the process-wide, thread-safe singleton client
client = Langfuse.client

# Manual flush (when not using block-based tracing)
Langfuse.flush

# Shutdown the client (idempotent; also runs via at_exit when shutdown_on_exit is true)
Langfuse.shutdown

# Reset the singleton (useful for testing; prefer Langfuse.new for isolated clients)
Langfuse.reset!
```

### 3. Nested Spans

```ruby
trace = client.trace(name: "document-qa")

# Create a span for document retrieval
retrieval_span = trace.span(
  name: "document-retrieval",
  input: { query: "What is machine learning?" }
)

# Add a generation for embedding
embedding_gen = retrieval_span.generation(
  name: "embedding-generation",
  model: "text-embedding-ada-002",
  input: "What is machine learning?",
  output: [0.1, 0.2, 0.3], # embedding vector
  usage: { prompt_tokens: 5, total_tokens: 5 }
)

# End the retrieval span
retrieval_span.end(
  output: { documents: ["ML is...", "Machine learning involves..."] }
)

# Create a span for answer generation
answer_span = trace.span(
  name: "answer-generation",
  input: { 
    query: "What is machine learning?",
    context: ["ML is...", "Machine learning involves..."]
  }
)

# Add LLM generation
llm_gen = answer_span.generation(
  name: "openai-completion",
  model: "gpt-3.5-turbo",
  input: [
    { role: "system", content: "Answer based on context" },
    { role: "user", content: "What is machine learning?" }
  ]
)

answer_span.end(output: { answer: "Machine learning is a subset of AI..." }, usage: { prompt_tokens: 50, completion_tokens: 30, total_tokens: 80 })
```

## Events

Create generic events for custom application events and logging:

```ruby
# Create events from trace
event = trace.event(
  name: "user_action",
  input: { action: "login", user_id: "123" },
  output: { success: true },
  metadata: { ip: "192.168.1.1" }
)

# Create events from spans or generations
validation_event = span.event(
  name: "validation_check",
  input: { rules: ["required", "format"] },
  output: { valid: true, warnings: [] }
)

# Direct event creation
event = client.event(
  trace_id: trace.id,
  name: "audit_log",
  input: { operation: "data_export" },
  output: { status: "completed" },
  level: "INFO"
)
```

## Prompt Management

### Get and Use Prompts

```ruby
# Get a prompt
prompt = client.get_prompt("chat-prompt", version: 1)

# Prompt names with special characters are automatically URL-encoded
prompt = client.get_prompt("EXEMPLE/my-prompt")  # Works correctly!

# Compile prompt with variables
compiled = prompt.compile(
  user_name: "Alice",
  topic: "machine learning"
)

puts compiled
# Output: "Hello Alice! Let's discuss machine learning today."
```

> **Note**: Prompt names containing special characters (like `/`, spaces, `?`, etc.) are automatically URL-encoded. You don't need to manually encode them.

### Create Prompts

```ruby
# Create a text prompt
text_prompt = client.create_prompt(
  name: "greeting-prompt",
  prompt: "Hello {{user_name}}! How can I help you with {{topic}} today?",
  labels: ["greeting", "customer-service"],
  config: { temperature: 0.7 }
)

# Create a chat prompt
chat_prompt = client.create_prompt(
  name: "chat-prompt",
  prompt: [
    { role: "system", content: "You are a helpful assistant specialized in {{domain}}." },
    { role: "user", content: "{{user_message}}" }
  ],
  labels: ["chat", "assistant"]
)
```

### Prompt Templates

```ruby
# Create prompt templates for reuse
template = Langfuse::PromptTemplate.from_template(
  "Translate the following text to {{language}}: {{text}}"
)

translated = template.format(
  language: "Spanish",
  text: "Hello, world!"
)

# Chat prompt templates
chat_template = Langfuse::ChatPromptTemplate.from_messages([
  { role: "system", content: "You are a {{role}} assistant." },
  { role: "user", content: "{{user_input}}" }
])

messages = chat_template.format(
  role: "helpful",
  user_input: "What is Ruby?"
)
```

## Evaluation and Scoring

### Built-in Evaluators

```ruby
# Exact match evaluator
exact_match = Langfuse::Evaluators::ExactMatchEvaluator.new

result = exact_match.evaluate(
  input: "What is 2+2?",
  output: "4",
  expected: "4"
)
# => { name: "exact_match", value: 1, comment: "Exact match" }

# Similarity evaluator
similarity = Langfuse::Evaluators::SimilarityEvaluator.new

result = similarity.evaluate(
  input: "What is AI?",
  output: "Artificial Intelligence is...",
  expected: "AI is artificial intelligence..."
)
# => { name: "similarity", value: 0.85, comment: "Similarity: 85%" }

# Length evaluator
length = Langfuse::Evaluators::LengthEvaluator.new(min_length: 10, max_length: 100)

result = length.evaluate(
  input: "Explain AI",
  output: "AI is a field of computer science that focuses on creating intelligent machines."
)
# => { name: "length", value: 1, comment: "Length 80 within range" }
```

### Custom Scoring

```ruby
# Add scores to traces or observations
trace = client.trace(name: "qa-session")

# Score the entire trace
trace.score(
  name: "user-satisfaction",
  value: 0.9,
  comment: "User was very satisfied"
)

# Score specific generations
generation = trace.generation(
  name: "answer-generation",
  model: "gpt-3.5-turbo",
  output: { content: "The answer is 42." }
)

generation.score(
  name: "accuracy",
  value: 0.8,
  comment: "Mostly accurate answer"
)

generation.score(
  name: "helpfulness",
  value: 0.95,
  comment: "Very helpful response"
)
```

## Advanced Usage

### Tracing Environment, Sampling and Masking

```ruby
# Tag all events with a tracing environment (also via LANGFUSE_TRACING_ENVIRONMENT)
client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  environment: "production"
)

# Sample a fraction of traces deterministically (also via LANGFUSE_SAMPLE_RATE)
# All events of a trace share the same keep/drop decision.
sampled_client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  sample_rate: 0.1
)

# Mask sensitive fields before sending (applied to input/output/metadata)
masked_client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  mask: ->(value) { value.to_s.gsub(/\b\d{16}\b, "***CARD***") }
)
```

### Batch flushing

Events are flushed in the background every `flush_interval` seconds, or as soon
as `flush_at` events are queued (default 15, env `LANGFUSE_FLUSH_AT`). Batches
are automatically split to respect the 3.5 MB ingestion API limit, and a
process-wide `at_exit` hook flushes pending events on shutdown.

```ruby
client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  flush_at: 50,           # flush after 50 events
  flush_interval: 10,     # or every 10 seconds
  shutdown_on_exit: true  # flush on process exit (default)
)
```

### Scores with full fields

Scores can target a trace, an observation, a session, or a dataset run, and
carry metadata, a config reference, and an annotation queue link:

```ruby
# Trace-level score
trace.score(name: "accuracy", value: 0.9, comment: "good")

# Observation-level score (trace_id is set automatically on Span/Generation)
generation.score(name: "faithfulness", value: 0.8, data_type: "NUMERIC")

# Session-level score
client.score(name: "csat", value: 5, session_id: "sess-1", data_type: "NUMERIC")

# Dataset-run score with metadata and config link
client.score(
  name: "hallucination",
  value: 0.2,
  dataset_run_id: "run-1",
  trace_id: "trace-1",
  metadata: { evaluator: "llm-judge" },
  config_id: "cfg-abc",
  data_type: "NUMERIC"
)

# Categorical string value
client.score(name: "label", value: "good", trace_id: "t1", data_type: "CATEGORICAL")
```

### Generation usage details, cost details and prompt linking

```ruby
# New v4 usage model (arbitrary keys, e.g. cache tokens)
gen = trace.generation(
  name: "chat",
  model: "gpt-4o",
  usage_details: { input: 100, output: 50, cache_read: 30 },
  cost_details: { input: 0.001, output: 0.003, total: 0.004 }
)
gen.end(output: "response")

# Link a generation to a prompt version (accepts a Langfuse::Prompt or a hash)
prompt = Langfuse.get_prompt("chat-prompt")
gen = trace.generation(name: "chat", model: "gpt-4o", prompt: prompt)
# or: prompt: { name: "chat-prompt", version: 3 }
```

### Error Handling

```ruby
begin
  client = Langfuse.new(
    public_key: "invalid-key",
    secret_key: "invalid-secret"
  )
  
  trace = client.trace(name: "test")
  client.flush
rescue Langfuse::AuthenticationError => e
  puts "Authentication failed: #{e.message}"
rescue Langfuse::RateLimitError => e
  puts "Rate limit exceeded: #{e.message}"
rescue Langfuse::NetworkError => e
  puts "Network error: #{e.message}"
rescue Langfuse::APIError => e
  puts "API error: #{e.message}"
end
```

### Configuration Options

```ruby
client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  host: "https://your-instance.langfuse.com",
  debug: true,          # Enable debug logging (or LANGFUSE_DEBUG=true)
  timeout: 30,          # Request timeout in seconds
  retries: 3,           # Number of retry attempts
  flush_interval: 30,   # Event flush interval in seconds (default: 5)
  flush_at: 50,         # Flush once this many events are queued (default: 15)
  auto_flush: true,     # Enable automatic flushing (default: true)
  environment: "prod",  # Tracing environment (or LANGFUSE_TRACING_ENVIRONMENT)
  sample_rate: 0.5,     # Keep 50% of traces deterministically (or LANGFUSE_SAMPLE_RATE)
  mask: ->(v) { v },    # Callable applied to input/output/metadata
  shutdown_on_exit: true # Flush pending events on process exit (default: true)
)
```

### Environment Variables

You can also configure the client using environment variables:

```bash
export LANGFUSE_PUBLIC_KEY="pk-lf-..."
export LANGFUSE_SECRET_KEY="sk-lf-..."
export LANGFUSE_HOST="https://cloud.langfuse.com"   # or LANGFUSE_BASE_URL
export LANGFUSE_FLUSH_INTERVAL=5
export LANGFUSE_FLUSH_AT=15
export LANGFUSE_AUTO_FLUSH=true
export LANGFUSE_TRACING_ENVIRONMENT="production"
export LANGFUSE_SAMPLE_RATE=0.5
export LANGFUSE_DEBUG=false
export LANGFUSE_INGESTION_MODE=legacy   # or otel
```

### Automatic Flush Control

By default, the Langfuse client automatically flushes events to the server at regular intervals using a background thread. You can control this behavior:

#### Enable/Disable Auto Flush

```ruby
# Enable automatic flushing (default)
client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  auto_flush: true,
  flush_interval: 5  # Flush every 5 seconds
)

# Disable automatic flushing for manual control
client = Langfuse.new(
  public_key: "pk-lf-...",
  secret_key: "sk-lf-...",
  auto_flush: false
)

# Manual flush when auto_flush is disabled
client.flush
```

#### Global Configuration

```ruby
Langfuse.configure do |config|
  config.auto_flush = false  # Disable auto flush globally
  config.flush_interval = 10
end
```

#### Environment Variable

```bash
export LANGFUSE_AUTO_FLUSH=false
```

#### Use Cases

**Auto Flush Enabled (Default)**
- Best for most applications
- Events are sent automatically
- No manual management required

**Auto Flush Disabled**
- Better performance for batch operations
- More control over when events are sent
- Requires manual flush calls
- Useful for high-frequency operations

```ruby
# Example: Batch processing with manual flush
client = Langfuse.new(auto_flush: false)

# Process many items
1000.times do |i|
  trace = client.trace(name: "batch-item-#{i}")
  # ... process item
end

# Flush all events at once
client.flush
```

### Shutdown

```ruby
# Ensure all events are flushed before shutdown
client.shutdown
```

## Framework Integration

### Rails Integration

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  config.public_key = Rails.application.credentials.langfuse_public_key
  config.secret_key = Rails.application.credentials.langfuse_secret_key
  config.debug = Rails.env.development?
end

# In your controller or service
class ChatController < ApplicationController
  def create
    @client = Langfuse.new
    
    trace = @client.trace(
      name: "chat-request",
      user_id: current_user.id,
      session_id: session.id,
      input: params[:message],
      metadata: { 
        controller: self.class.name,
        action: action_name,
        ip: request.remote_ip
      }
    )
    
    # Your LLM logic here
    response = generate_response(params[:message])

    render json: { response: response }
  end
end
```

### Sidekiq Integration

```ruby
class LLMProcessingJob < ApplicationJob
  def perform(user_id, message)
    client = Langfuse.new

    trace = client.trace(
      name: "background-llm-processing",
      user_id: user_id,
      input: { message: message },
      metadata: { job_class: self.class.name }
    )

    # Process with LLM
    result = process_with_llm(message)

    # Ensure events are flushed
    client.flush
  end
end
```

## Examples

Check out the `examples/` directory for more comprehensive examples:

- [Basic Tracing](examples/basic_tracing.rb)
- [Prompt Management](examples/prompt_management.rb)
- [Evaluation Pipeline](examples/evaluation_pipeline.rb)
- [Rails Integration](examples/rails_integration.rb)

## Documentation

For more detailed information, please refer to the [documentation](docs/README.md).

- [Publishing Guide](docs/PUBLISH_GUIDE.md)
- [Release Checklist](docs/RELEASE_CHECKLIST.md)
- [Examples](examples/)

## Development

After checking out the repo, run:

```bash
bin/setup
```

To install dependencies. Then, run:

```bash
rake spec
```

To run the tests. You can also run:

```bash
bin/console
```

For an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ai-firstly/langfuse-ruby.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Links

- [Langfuse Ruby SDK Documentation](https://rubydoc.info/gems/langfuse-ruby)
- [RubyGems](https://rubygems.org/gems/langfuse-ruby)
- [Langfuse Documentation](https://langfuse.com/docs) 
