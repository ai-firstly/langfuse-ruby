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

# Release: bump version + CHANGELOG, then `make tag VERSION=x.y.z`
# (pushes v* tag; GitHub Actions publishes to RubyGems)
```

## Architecture

### Core Classes

- **`Langfuse`** ([lib/langfuse.rb](lib/langfuse.rb)) - Module with class-level convenience methods (`trace`, `get_prompt`, `client`, `flush`, `shutdown`, `reset!`)
- **`Langfuse::Client`** ([lib/langfuse/client.rb](lib/langfuse/client.rb)) - Main entry point. Handles API authentication, HTTP connections (via Faraday), event queuing, sampling/masking, and background flush thread for auto-batching events.
- **`Langfuse::Trace`** ([lib/langfuse/trace.rb](lib/langfuse/trace.rb)) - Top-level container for a request/session.
- **`Langfuse::Span`** ([lib/langfuse/span.rb](lib/langfuse/span.rb)) - Timed operation with enhanced type support.
- **`Langfuse::Generation`** ([lib/langfuse/generation.rb](lib/langfuse/generation.rb)) - LLM call tracking (supports `usage_details`/`cost_details` and prompt linking).
- **`Langfuse::Event`** ([lib/langfuse/event.rb](lib/langfuse/event.rb)) - Point-in-time events.
- **`Langfuse::SpanWrappers`** ([lib/langfuse/span_wrappers.rb](lib/langfuse/span_wrappers.rb)) - Generates the enhanced observation helpers (`agent`, `tool`, `chain`, `retriever`, `evaluator`, `guardrail`) for Client/Trace/Span/Generation as `#span` calls with a fixed `as_type`.
- **`Langfuse::Prompt`** ([lib/langfuse/prompt.rb](lib/langfuse/prompt.rb)) - Prompt templates.
- **`Langfuse::TemplateCompiler`** ([lib/langfuse/template_compiler.rb](lib/langfuse/template_compiler.rb)) - `{{var}}` / `{var}` substitution and variable extraction shared by `Prompt`, `PromptTemplate` and `ChatPromptTemplate`.
- **`Langfuse::PromptCache`** ([lib/langfuse/prompt_cache.rb](lib/langfuse/prompt_cache.rb)) - Bounded, thread-safe prompt cache used by `Client#get_prompt`: monotonic-clock TTLs, oldest-first eviction, stale reads for outage fallback.
- **`Langfuse::PartialUpdates`** ([lib/langfuse/partial_updates.rb](lib/langfuse/partial_updates.rb)) - Dirty tracking for `Trace`/`Span`/`Generation`: `update`/`end` record which fields the caller passed, and `update_body` slices `to_dict` down to those plus the identifying fields (`id`, `trace_id`, `type`).
- **`Langfuse::OtelExporter`** ([lib/langfuse/otel_exporter.rb](lib/langfuse/otel_exporter.rb)) - Maps Langfuse events to OTLP/HTTP JSON when `ingestion_mode: :otel`.
- **`Langfuse::NullTrace/NullGeneration/NullSpan`** ([lib/langfuse/null_objects.rb](lib/langfuse/null_objects.rb)) - Null objects for graceful degradation.

New projects should set `ingestion_mode: :otel` (Langfuse v4 / OTLP). The
default remains `:legacy` for compatibility; Cloud stops accepting non-score
`/api/public/ingestion` traffic on 16 November 2026. See [docs/V4.md](docs/V4.md).

### Simplified API (Recommended)

```ruby
Langfuse.configure { |c| c.ingestion_mode = :otel }  # Langfuse v4

# Block-based tracing with automatic flush
Langfuse.trace("my-trace", user_id: "user-1") do |trace|
  gen = trace.generation(name: "openai", model: "gpt-4", input: messages)
  response = call_llm(...)
  gen.end(output: response, usage_details: { input: 10, output: 20, total: 30 })
end  # Auto flush!

# Get prompt with variables and retry
Langfuse.get_prompt("my-prompt", variables: { name: "Alice" }, retries: 3)
```

### Event Flow

1. Observations (traces, spans, generations, events, scores) are created via Client methods
2. Bodies are prepared via `Utils.prepare_event_body` (top-level camelCase; user data under `input`/`output`/`metadata`/etc. is left verbatim), then environment injection, masking, and sampling are applied
3. Events are queued in `@event_queue` (thread-safe `Concurrent::Array`, guarded by `@queue_mutex`). The queue is bounded by `max_queue_size` (default 10,000); when full, the oldest events are dropped with a rate-limited warning. `trace-update` events merge into the queued `trace-create` under the same lock; if the create has already flushed, the update is converted to a create from `trace_ref.to_dict` and re-run through the same camelCase / environment / mask path
4. Background flush thread wakes on `flush_interval` **or** when the queue reaches `flush_at`. It is recreated after `fork` (events inherited from the parent are dropped; the parent still flushes them) and stopped gracefully on `shutdown` (signalled, joined with a 5 s grace period, killed only as a fallback)
5. `*-update` events carry only the changed fields (see `PartialUpdates`), so a long generation's input is not re-sent when it ends
6. Flush path depends on `ingestion_mode` (both paths chunk to 3.5 MB):
   - `:legacy` → batched POST to `/api/public/ingestion`
   - `:otel` → non-score events via OTLP `/api/public/otel/v1/traces`, after collapsing each observation's `*-create`/`*-update` events into one span (v4 is append-only, so exporting both would duplicate the observation); **scores always go through the ingestion API**, with IDs normalized to OTel hex so they attach correctly. On OTEL transport failure, the not-yet-sent chunks and the batch's score events are re-queued; `partialSuccess` responses are logged as warnings
   - On failure both paths re-queue only for transient errors; permanent failures (4xx validation/auth) drop the batch with a warning so it cannot block the queue forever
   - The legacy batch is serialized to JSON once and posted as a String; the per-event chunking path only runs when that payload exceeds 3.5 MB
7. Manual flush via `client.flush`; idempotent shutdown via `client.shutdown` (plus optional `at_exit` hook)

### Observation Types

The SDK supports enhanced observation types defined in `ObservationType` module:
- Core: `span`, `generation`, `event`
- Enhanced: `agent`, `tool`, `chain`, `retriever`, `embedding`, `evaluator`, `guardrail`

Enhanced types are implemented as spans with `as_type` metadata sent to the API.

### Configuration

Client accepts config via:
1. Constructor parameters
2. `Langfuse.configure` block
3. Environment variables: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST` / `LANGFUSE_BASE_URL`, `LANGFUSE_FLUSH_INTERVAL`, `LANGFUSE_FLUSH_AT`, `LANGFUSE_MAX_QUEUE_SIZE`, `LANGFUSE_AUTO_FLUSH`, `LANGFUSE_TRACING_ENVIRONMENT`, `LANGFUSE_SAMPLE_RATE`, `LANGFUSE_DEBUG`, `LANGFUSE_INGESTION_MODE` (`otel` for v4, `legacy` for pre-v4)

Default host is `https://us.cloud.langfuse.com`. Default `ingestion_mode` is `:legacy`; use `:otel` for Langfuse v4.

`http_adapter` is constructor/`configure`-only (no env var), since the adapter has to be in the app's `Gemfile` anyway.

### Error Handling

Custom exceptions in [lib/langfuse/errors.rb](lib/langfuse/errors.rb):
- `AuthenticationError`, `APIError`, `NetworkError`, `ValidationError`, `RateLimitError`, `TimeoutError`

Graceful degradation: When trace creation fails, `Langfuse.trace` yields a `NullTrace` that silently no-ops all operations. Only creation is rescued — an exception raised by the block propagates and the block is never re-run (re-running it would duplicate LLM calls).

Retries live in `Client#request` only: `TimeoutError`, `NetworkError`, `RateLimitError` and 5xx `APIError` are retried up to `retries` times (per-call override via `retries:`), honoring `Retry-After` (seconds or HTTP date, capped at `MAX_RETRY_DELAY_SECONDS`) and otherwise backing off exponentially from `RETRY_BASE_DELAY_SECONDS` with ±50% jitter. `Langfuse.get_prompt` passes `retries:` down instead of running its own loop (the two used to multiply).

## Key Implementation Details

- Uses Faraday for HTTP with Basic Auth (public_key:secret_key); `http_adapter` selects the adapter (e.g. `:net_http_persistent` for keep-alive) and falls back to `Faraday.default_adapter` with a warning when the adapter's gem is missing
- Prompt names with special characters are auto-URL-encoded via `Utils.url_encode`
- `trace-update` events merge into the queued `trace-create` under `@queue_mutex` (deduplication without flush races). A reconstruction from `trace_ref` (create already flushed) goes through `prepare_queued_body` so keys stay camelCase, the default environment is injected, and the mask still applies
- `get_prompt` caches via `PromptCache`: on refetch failure the stale entry is served with a warning rather than raising
- `Client#inspect` redacts the secret key
- The enhanced observation wrappers are generated by `SpanWrappers#define_span_wrappers` (Client names the evaluator helper `evaluator_obs` and aliases `evaluator` to it); `embedding` stays hand-written in each class because it folds model/usage into metadata
- `Trace`/`Span`/`Event` enqueue `to_dict`, so `to_dict` is the single place a body field is defined (`Generation` already worked this way)
- `TemplateCompiler.compile` substitutes all variables in one pass over the template, so a variable value containing `{{...}}` is never expanded again; unknown placeholders are left untouched
- Event bodies use `Utils.prepare_event_body` (top-level camelCase only; nested user data is not mangled)
- Process-wide singleton client via `Langfuse::CLIENT_MUTEX` (not thread-local); use `Langfuse.new` for isolated clients in tests
- In OTel mode, IDs are W3C hex (`generate_trace_id` / `generate_observation_id`); scores normalize refs via `OtelExporter.to_otel_trace_id` / `to_otel_span_id`
- In OTel mode, a legacy `usage` object is normalized into `langfuse.observation.usage_details` (v4's cost model) unless `usage_details` was set explicitly; non-token `unit`s are skipped
- Typed errors from `handle_response` keep their class through `#request`; only unexpected errors are wrapped in `APIError`
- `get_prompt` supports configurable retries with exponential backoff
