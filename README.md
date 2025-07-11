# Langfuse Ruby SDK

[![Gem Version](https://badge.fury.io/rb/langfuse.svg)](https://badge.fury.io/rb/langfuse)
[![Build Status](https://github.com/your-username/langfuse-ruby/workflows/CI/badge.svg)](https://github.com/your-username/langfuse-ruby/actions)

Ruby SDK for [Langfuse](https://langfuse.com) - the open-source LLM engineering platform. This SDK provides comprehensive tracing, prompt management, and evaluation capabilities for LLM applications.

## Features

- 🔍 **Tracing**: Complete observability for LLM applications with traces, spans, and generations
- 📝 **Prompt Management**: Version control and deployment of prompts with caching
- 📊 **Evaluation**: Built-in evaluators and custom scoring capabilities
- 🚀 **Async Processing**: Background event processing with automatic batching
- 🔒 **Type Safety**: Comprehensive error handling and validation
- 🎯 **Framework Integration**: Easy integration with popular Ruby frameworks

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'langfuse'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install langfuse
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

### 2. Basic Tracing

```ruby
# Create a trace
trace = client.trace(
  name: "chat-completion",
  user_id: "user123",
  session_id: "session456",
  input: { message: "Hello, world!" },
  metadata: { environment: "production" }
)

# Add a generation (LLM call)
generation = trace.generation(
  name: "openai-completion",
  model: "gpt-3.5-turbo",
  input: [{ role: "user", content: "Hello, world!" }],
  output: { content: "Hello! How can I help you today?" },
  usage: { prompt_tokens: 10, completion_tokens: 15, total_tokens: 25 },
  model_parameters: { temperature: 0.7, max_tokens: 100 }
)

# Update trace with final output
trace.update(
  output: { response: "Hello! How can I help you today?" }
)

# Flush events (optional - happens automatically)
client.flush
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
  ],
  output: { content: "Machine learning is a subset of AI..." },
  usage: { prompt_tokens: 50, completion_tokens: 30, total_tokens: 80 }
)

answer_span.end(output: { answer: "Machine learning is a subset of AI..." })
```

## Prompt Management

### Get and Use Prompts

```ruby
# Get a prompt
prompt = client.get_prompt("chat-prompt", version: 1)

# Compile prompt with variables
compiled = prompt.compile(
  user_name: "Alice",
  topic: "machine learning"
)

puts compiled
# Output: "Hello Alice! Let's discuss machine learning today."
```

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
  debug: true,        # Enable debug logging
  timeout: 30,        # Request timeout in seconds
  retries: 3          # Number of retry attempts
)
```

### Environment Variables

You can also configure the client using environment variables:

```bash
export LANGFUSE_PUBLIC_KEY="pk-lf-..."
export LANGFUSE_SECRET_KEY="sk-lf-..."
export LANGFUSE_HOST="https://cloud.langfuse.com"
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
    
    trace.update(output: { response: response })
    
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
    
    trace.update(output: result)
    
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

Bug reports and pull requests are welcome on GitHub at https://github.com/your-username/langfuse-ruby.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Links

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [API Reference](https://api.reference.langfuse.com)
- [Ruby SDK Documentation](https://rubydoc.info/gems/langfuse) 