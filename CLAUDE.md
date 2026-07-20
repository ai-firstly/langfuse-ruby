# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the official Ruby SDK for [Langfuse](https://langfuse.com) - an open-source LLM engineering platform. The SDK provides tracing, prompt management, and evaluation capabilities for LLM applications.

## Common Commands

Ruby version is managed with [mise](https://mise.jdx.dev) via `.mise.toml`
(defaults to the latest stable Ruby). Run `mise install` after cloning, then
`bundle install`. With mise's shell integration active, the commands below work
directly; in a non-mise shell prefix them with `mise exec --`.

```bash
# Install dependencies
mise install        # install the pinned Ruby version
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
- **`Langfuse::Client`** ([lib/langfuse/client.rb](lib/langfuse/client.rb)) - Main entry point. Handles API authentication, HTTP connections (via Faraday), event queuing, sampling/masking, and background flush thread for auto-batching events.
- **`Langfuse::Trace`** ([lib/langfuse/trace.rb](lib/langfuse/trace.rb)) - Top-level container for a request/session.
- **`Langfuse::Span`** ([lib/langfuse/span.rb](lib/langfuse/span.rb)) - Timed operation with enhanced type support.
- **`Langfuse::Generation`** ([lib/langfuse/generation.rb](lib/langfuse/generation.rb)) - LLM call tracking (supports `usage_details`/`cost_details` and prompt linking).
- **`Langfuse::Event`** ([lib/langfuse/event.rb](lib/langfuse/event.rb)) - Point-in-time events.
- **`Langfuse::Prompt`** ([lib/langfuse/prompt.rb](lib/langfuse/prompt.rb)) - Prompt templates with caching.
- **`Langfuse::OtelExporter`** ([lib/langfuse/otel_exporter.rb](lib/langfuse/otel_exporter.rb)) - Maps Langfuse events to OTLP/HTTP JSON when `ingestion_mode: :otel`.
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

1. Observations (traces, spans, generations, events, scores) are created via Client methods
2. Bodies are prepared via `Utils.prepare_event_body` (top-level camelCase; user data under `input`/`output`/`metadata`/etc. is left verbatim), then environment injection, masking, and sampling are applied
3. Events are queued in `@event_queue` (thread-safe `Concurrent::Array`)
4. Background flush thread wakes on `flush_interval` **or** when the queue reaches `flush_at`
5. Flush path depends on `ingestion_mode`:
   - `:legacy` → batched POST to `/api/public/ingestion` (chunked to 3.5 MB)
   - `:otel` → non-score events via OTLP `/api/public/otel/v1/traces`; **scores always go through the ingestion API**, with IDs normalized to OTel hex so they attach correctly. On OTEL transport failure, both OTEL and score events from the batch are re-queued
6. Manual flush via `client.flush`; idempotent shutdown via `client.shutdown` (plus optional `at_exit` hook)

### Observation Types

The SDK supports enhanced observation types defined in `ObservationType` module:
- Core: `span`, `generation`, `event`
- Enhanced: `agent`, `tool`, `chain`, `retriever`, `embedding`, `evaluator`, `guardrail`

Enhanced types are implemented as spans with `as_type` metadata sent to the API.

### Configuration

Client accepts config via:
1. Constructor parameters
2. `Langfuse.configure` block
3. Environment variables: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST` / `LANGFUSE_BASE_URL`, `LANGFUSE_FLUSH_INTERVAL`, `LANGFUSE_FLUSH_AT`, `LANGFUSE_AUTO_FLUSH`, `LANGFUSE_TRACING_ENVIRONMENT`, `LANGFUSE_SAMPLE_RATE`, `LANGFUSE_DEBUG`, `LANGFUSE_INGESTION_MODE`

### Error Handling

Custom exceptions in [lib/langfuse/errors.rb](lib/langfuse/errors.rb):
- `AuthenticationError`, `APIError`, `NetworkError`, `ValidationError`, `RateLimitError`, `TimeoutError`

Graceful degradation: When Langfuse is unavailable, `Langfuse.trace` yields a `NullTrace` that silently no-ops all operations.

## Key Implementation Details

- Uses Faraday for HTTP with Basic Auth (public_key:secret_key)
- Prompt names with special characters are auto-URL-encoded via `Utils.url_encode`
- `trace-update` events merge into existing `trace-create` in queue (deduplication)
- Event bodies use `Utils.prepare_event_body` (top-level camelCase only; nested user data is not mangled)
- Process-wide singleton client via `Langfuse::CLIENT_MUTEX` (not thread-local); use `Langfuse.new` for isolated clients in tests
- In OTel mode, IDs are W3C hex (`generate_trace_id` / `generate_observation_id`); scores normalize refs via `OtelExporter.to_otel_trace_id` / `to_otel_span_id`
- `get_prompt` supports configurable retries with exponential backoff
