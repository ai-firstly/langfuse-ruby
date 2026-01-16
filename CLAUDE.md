# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the official Ruby SDK for [Langfuse](https://langfuse.com) - an open-source LLM engineering platform. The SDK provides tracing, prompt management, and evaluation capabilities for LLM applications.

## Common Commands

```bash
# Install dependencies
bundle install

# Run all RSpec tests
bundle exec rake spec

# Run a single test file
bundle exec rspec spec/langfuse/client_spec.rb

# Run offline tests (no network required)
bundle exec rake test_offline

# Run all tests (spec + offline)
bundle exec rake test_all

# Lint code
bundle exec rubocop

# Build the gem
bundle exec rake build

# Release to RubyGems
bundle exec rake release_gem
```

## Architecture

### Core Classes

- **`Langfuse`** ([lib/langfuse.rb](lib/langfuse.rb)) - Module with class-level convenience methods (`trace`, `get_prompt`, `client`, `flush`, `shutdown`, `reset!`)
- **`Langfuse::Client`** ([lib/langfuse/client.rb](lib/langfuse/client.rb)) - Main entry point. Handles API authentication, HTTP connections (via Faraday), event queuing, and background flush thread for auto-batching events.
- **`Langfuse::Trace`** ([lib/langfuse/trace.rb](lib/langfuse/trace.rb)) - Top-level container for a request/session.
- **`Langfuse::Span`** ([lib/langfuse/span.rb](lib/langfuse/span.rb)) - Timed operation with enhanced type support.
- **`Langfuse::Generation`** ([lib/langfuse/generation.rb](lib/langfuse/generation.rb)) - LLM call tracking.
- **`Langfuse::Event`** ([lib/langfuse/event.rb](lib/langfuse/event.rb)) - Point-in-time events.
- **`Langfuse::Prompt`** ([lib/langfuse/prompt.rb](lib/langfuse/prompt.rb)) - Prompt templates with caching.
- **`Langfuse::NullTrace/NullGeneration/NullSpan`** ([lib/langfuse/null_objects.rb](lib/langfuse/null_objects.rb)) - Null objects for graceful degradation.

### Simplified API (Recommended)

```ruby
# Block-based tracing with automatic flush
Langfuse.trace("my-trace", user_id: "user-1") do |trace|
  gen = trace.generation(name: "openai", model: "gpt-4", input: messages)
  response = call_llm(...)
  gen.end(output: response, usage: usage)
end  # Auto flush!

# Get prompt with variables and retry
Langfuse.get_prompt("my-prompt", variables: { name: "Alice" }, retries: 3)
```

### Event Flow

1. Observations (traces, spans, generations, events) are created via Client methods
2. Events are queued in `@event_queue` (thread-safe `Concurrent::Array`)
3. Background flush thread sends batched events to `/api/public/ingestion` endpoint
4. Manual flush available via `client.flush`; graceful shutdown via `client.shutdown`

### Observation Types

The SDK supports enhanced observation types defined in `ObservationType` module:
- Core: `span`, `generation`, `event`
- Enhanced: `agent`, `tool`, `chain`, `retriever`, `embedding`, `evaluator`, `guardrail`

Enhanced types are implemented as spans with `as_type` metadata sent to the API.

### Configuration

Client accepts config via:
1. Constructor parameters
2. `Langfuse.configure` block
3. Environment variables: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`, `LANGFUSE_FLUSH_INTERVAL`, `LANGFUSE_AUTO_FLUSH`

### Error Handling

Custom exceptions in [lib/langfuse/errors.rb](lib/langfuse/errors.rb):
- `AuthenticationError`, `APIError`, `NetworkError`, `ValidationError`, `RateLimitError`, `TimeoutError`

Graceful degradation: When Langfuse is unavailable, `Langfuse.trace` yields a `NullTrace` that silently no-ops all operations.

## Key Implementation Details

- Uses Faraday for HTTP with Basic Auth (public_key:secret_key)
- Prompt names with special characters are auto-URL-encoded via `Utils.url_encode`
- `trace-update` events merge into existing `trace-create` in queue (deduplication)
- All keys are converted to camelCase before API submission via `Utils.deep_camelize_keys`
- Thread-safe singleton client via `Thread.current[:langfuse_client]`
- `get_prompt` supports configurable retries with exponential backoff
