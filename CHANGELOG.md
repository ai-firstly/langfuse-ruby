# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **`Langfuse.trace` executed the block twice**: an exception raised inside the block was caught by the method-level `rescue` and the block was re-run with a `NullTrace` — duplicating LLM calls and their cost. Only trace creation degrades to `NullTrace` now; exceptions from the block propagate untouched
- **Typed API errors collapsed into `APIError`**: `AuthenticationError` / `RateLimitError` / `ValidationError` raised by `handle_response` were re-wrapped by the generic `rescue` in `#request`, so callers could not rescue them selectively
- **`Langfuse.configure` values for `timeout` / `retries` were ignored**: the `Client#initialize` defaults (30 / 3) shadowed the configured values
- **OTel mode dropped token usage**: only `promptTokens` / `completionTokens` were mapped. All legacy shapes (`promptTokens`, `inputTokens`, `input`) now map to `gen_ai.usage.*` and are normalized into `langfuse.observation.usage_details`, which is what Langfuse v4 uses for cost. Usage carrying a non-token `unit` is skipped instead of being reported as tokens
- **OTel mode produced duplicate observations**: the `*-create` and `*-update` events of one observation were exported as two spans sharing a span id, which the append-only v4 data model stores twice. They are collapsed into one span carrying the final state
- **OTel mode stringified structured attributes**: hashes and arrays (for example `model_parameters[:tools]`) were sent through Ruby's `inspect`; they are JSON-encoded now
- **OTel export leaked raw Faraday errors**: failures on the OTLP connection now surface as `TimeoutError` / `NetworkError` / `APIError`, matching the ingestion API path
- **`shutdown` killed the flush thread mid-send**: events already drained from the queue were lost. The thread is now signalled to stop and joined (5 s grace period, kill only as a fallback)
- **Flush thread was not fork-safe**: after `fork` (e.g. Puma workers) the child inherited a dead thread and the parent's queued events. Each process now recreates its own flush thread and drops inherited events instead of sending them twice
- **Permanently failing batches were re-queued forever**: a 4xx (validation/auth) failure re-queued the same events on every flush, blocking the queue. They are now dropped with a warning; transient failures (5xx, network) are still re-queued
- **Event queue races**: enqueue, the `trace-update` → `trace-create` merge, and the flush drain ran without a shared lock, so a concurrent flush could interleave with a merge. They are serialized by a queue mutex now
- **Prompt compilation re-expanded placeholders coming from variable values**: variables were substituted one after another, so a value containing `{{other_var}}` was expanded by a later round (user input could inject template syntax, and the result depended on hash order). All variables are now substituted in a single pass, and a value containing a placeholder stays literal
- **`Span#generation` and `Generation#generation` dropped `usage_details`, `cost_details` and `prompt`**: the parameters were missing from both signatures, so a generation created under a span or another generation silently lost its v4 cost data and prompt link (only `Trace#generation` forwarded them)
- **Retries hit non-retryable failures**: `#request` retried every error, so a 401 or a 422 was sent four times before failing. Only timeouts, network errors, 429 and 5xx are retried now
- **Retries ignored `Retry-After`**: a rate-limited request was retried on a fixed 1 s / 2 s / 3 s schedule regardless of the server's instruction, and all clients retried in lockstep because the delay carried no jitter
- **`Langfuse.get_prompt` retried twice over**: its own retry loop wrapped the HTTP layer's retries, so one call could issue up to nine requests (and a missing prompt was fetched three times before returning `nil`). Retries now happen in one place
- **An unknown `ingestion_mode` silently behaved like `:legacy`**: a typo such as `LANGFUSE_INGESTION_MODE=otlp` looked like a working v4 setup. The value is now normalized (`"OTEL"` → `:otel`) and validated, with a warning when it is not recognized
- **A flushed `trace-update` sent unprocessed `to_dict` output**: when the matching `trace-create` was already gone from the queue, the reconstructed body used symbol/snake_case keys and skipped environment injection and the `mask` callable, so the API could reject the event and PII could leave unredacted. The reconstruction now re-runs the same prepare/env/mask path as every other enqueue

### Added
- OTLP payloads are chunked to the 3.5 MB batch limit (previously only the ingestion API path was chunked)
- OTLP `partialSuccess` responses (HTTP 200 with rejected spans) are logged as warnings instead of silently losing data
- `max_queue_size` config (constructor / `Langfuse.configure` / `LANGFUSE_MAX_QUEUE_SIZE`, default 10,000): the event queue is bounded; when full, the oldest events are dropped with a rate-limited warning instead of growing memory without bound
- `get_prompt` resilience: when a refetch fails, the expired cache entry is served with a warning instead of raising (a Langfuse outage no longer breaks prompt resolution for previously fetched prompts). The prompt cache is now bounded (200 entries) and measures TTLs on the monotonic clock, so wall-clock jumps cannot extend or shorten entry lifetimes
- `Client#inspect` redacts the secret key, keeping it out of logs and console output
- `http_adapter` config (constructor / `Langfuse.configure`): selects the Faraday adapter, so a connection-pooling adapter such as `:net_http_persistent` can be used to keep the TLS connection alive between flushes. Defaults to Faraday's default adapter; an adapter whose gem is missing logs a warning and falls back instead of raising

### Changed
- Retries are now applied only to transient failures (`TimeoutError`, `NetworkError`, `RateLimitError`, 5xx `APIError`), honor `Retry-After` (seconds or HTTP date, capped at 10 s), and otherwise back off exponentially from 0.5 s with ±50% jitter, capped at 10 s. `retries:` can be overridden per request
- Ingestion batches are serialized to JSON once and posted as a pre-encoded body; the per-event chunking path only runs when the batch exceeds the 3.5 MB limit (previously every batch was measured event by event and then re-encoded by Faraday)
- `*-update` events send only the fields that actually changed, plus the identifying ones, instead of the observation's full body. Ending a long generation no longer re-uploads its input and model parameters
- Enhanced observation wrappers (`agent`, `tool`, `chain`, `retriever`, `evaluator`, `guardrail`) are generated once in the new `Langfuse::SpanWrappers` module and shared by `Client`, `Trace`, `Span` and `Generation`, replacing 24 hand-written copies (~400 lines); an explicit `as_type:` passed by the caller no longer overrides the wrapper's type
- `Client#evaluator` is available as an alias of `Client#evaluator_obs`, so the helper has the same name as `Trace#evaluator` / `Span#evaluator` / `Generation#evaluator` (both names keep working)
- Placeholder compilation and variable extraction moved into the new `Langfuse::TemplateCompiler`, shared by `Prompt`, `PromptTemplate` and `ChatPromptTemplate` (previously four copies of the substitution loop and three of the variable scanner)
- `Trace`, `Span` and `Event` now serialize through `to_dict` when enqueuing `*-create` / `*-update` events instead of rebuilding the same hash in each method, so a field can no longer be added to one path and forgotten in the others
- `Utils.deep_stringify_keys` is now an alias of `Utils.deep_camelize_keys`: the two implementations were identical, and both camelize keys rather than only stringifying them

## [0.2.0] - 2026-07-18

### Added
- **Environment support**: `environment` config / `LANGFUSE_TRACING_ENVIRONMENT` env var, injected into trace, observation and score bodies
- **Sampling**: `sample_rate` config / `LANGFUSE_SAMPLE_RATE` env var, deterministic trace-based sampling (all events of a trace share the same decision)
- **Masking**: `mask` callable applied to `input`/`output`/`metadata` before sending, for PII redaction
- **flush_at threshold**: flush as soon as the queue reaches `flush_at` events (default 15, env `LANGFUSE_FLUSH_AT`), via a condition-variable wake-up on the flush thread
- **Batch chunking**: ingestion batches are split to respect the 3.5 MB API limit; oversized single events are dropped with a warning
- **207 partial-success handling**: per-event errors from the ingestion API are logged via the structured logger
- **Score full fields**: `session_id`, `dataset_run_id`, `metadata`, `config_id`, `queue_id`, `id`, `environment`, and string values for CATEGORICAL/CORRECTION scores; `create_score` alias
- **Generation usage_details / cost_details**: new v4 usage model (arbitrary keys such as cache tokens) alongside legacy `usage`
- **Generation prompt linking**: `prompt:` accepts a `Langfuse::Prompt` or `{ name:, version: }` hash, emitted as `promptName`/`promptVersion`
- **Trace public field**: `public:` flag for shareable traces
- **LANGFUSE_BASE_URL** env var alias (new SDK standard) alongside `LANGFUSE_HOST`
- **Structured Logger**: replaces `puts` with `Logger`; level controlled by `debug` / `LANGFUSE_DEBUG`
- **at_exit shutdown hook**: pending events are flushed on process exit (configurable via `shutdown_on_exit`)
- **W3C hex IDs in OTel mode**: native 32-char trace IDs and 16-char span IDs for OTel ingestion
- **OTel exporter attributes**: `langfuse.environment`, `langfuse.trace.public`, `langfuse.internal.as_root`, `langfuse.observation.usage_details`, `langfuse.observation.cost_details`, `langfuse.observation.prompt.name`, `langfuse.observation.prompt.version`
- **Simplified API**: Class-level convenience methods (`Langfuse.trace`, `get_prompt`, `client`, `flush`, `shutdown`, `reset!`) with graceful degradation via null objects
- **Retry Support**: `get_prompt` supports configurable retries with exponential backoff (default: 2 retries)
- **Ruby 4.0 support**: CI matrix covers Ruby 3.1–4.0; explicit `base64` / `tsort` dependencies for Ruby 4.0 gem packaging

### Fixed
- **OTel mode scores lost**: scores were exported as OTLP spans with `langfuse.score.*` attributes, which the server does not map to Langfuse scores. Scores now always route through the ingestion API (`score-create` batch), with trace/observation IDs normalized to OTel hex IDs so they attach to the correct entities
- **OTel flush failure drops scores**: when OTEL export of non-score events fails, score events in the same batch are now re-queued together with OTEL events (they were previously drained by `flush` and permanently lost on `raise`)
- **OTel ID mismatch**: observation-level scores referenced full UUIDs while spans used truncated hex, breaking attachment. IDs are now normalized on both sides
- **Span/Generation score missing trace_id**: `Span#score` and `Generation#score` now pass `trace_id` so the server can attach observation-level scores correctly
- **Process-level singleton**: `Langfuse.client` was thread-local (`Thread.current`), creating one client + flush thread per thread under Puma/Sidekiq. Now a single process-wide client guarded by a `Mutex`
- **Idempotent shutdown**: `shutdown` can be called multiple times safely
- **Body serialization**: event bodies now only camelCase top-level keys; user data under `input`/`output`/`metadata`/`usageDetails`/`costDetails`/`modelParameters` is passed through verbatim so user-provided keys are not mangled

### Changed
- `Langfuse.client` is now process-wide instead of thread-local. Use `Langfuse.new` for isolated clients in tests
- Default `flush_interval` behavior unchanged, but the flush thread now also wakes on the `flush_at` threshold
- `Configuration` gains `environment`, `sample_rate`, `mask`, `flush_at`, `logger`, `shutdown_on_exit` attributes

## [0.1.5] - 2025-12-26

### Added
- Support for all enhanced observation types: `agent`, `tool`, `chain`, `retriever`, `embedding`, `evaluator`, `guardrail`
- New `ObservationType` module with constants for all observation types
- Convenience methods on `Client` and `Trace` for creating enhanced observations
- New `as_type` parameter on `span()` method for specifying observation type
- Comprehensive test coverage for enhanced observation types

### Fixed
- Fixed URL encoding for prompt names containing special characters (/, spaces, etc.) in `get_prompt` method
- Prompt names are now automatically URL-encoded before being interpolated into API paths

### Changed
- Updated Ruby version requirement to >= 3.1.0
- Environment variables moved from metadata to top-level trace attributes

### Internal
- Added `Utils.url_encode` helper method for consistent URL encoding across the SDK
- CI improvements for offline test execution

## [0.1.4] - 2025-07-29

### Added
- Added support for `trace` event type in Langfuse ingestion API
- Added support for `event-create` event type in Langfuse ingestion API
- New `Event` class for creating generic events within traces, spans, and generations
- Added `event()` method to `Client`, `Trace`, `Span`, and `Generation` classes
- Enhanced event validation to include all supported Langfuse event types
- New example file `examples/event_usage.rb` demonstrating event functionality

### Fixed
- Improved offline test error handling and authentication validation
- Enhanced error handling tests with proper configuration management
- Fixed prompt template validation tests in offline mode
- Better error message handling for authentication failures

### Improved
- More comprehensive error handling test coverage
- Better test isolation and cleanup procedures
- Enhanced debugging capabilities for offline testing

## [0.1.3] - 2025-07-13

### Fixed
- Enhanced event data validation and debugging capabilities
- More detailed error messages for event structure validation failures

## [0.1.2] - 2025-07-12

### Fixed
- Enhanced event data validation and debugging capabilities
- More detailed error messages for event structure validation failures

## [0.1.1] - 2025-07-12

### Fixed
- Improved error handling for `get_prompt` method when prompt doesn't exist
- Better error messages for 404 responses that return HTML instead of JSON
- Enhanced debugging capabilities with detailed request/response logging

### Added
- Comprehensive troubleshooting guide for prompt management issues
- Better detection of HTML responses vs JSON responses
- More specific error types for different failure scenarios

### Changed
- Updated gemspec metadata to avoid RubyGems warnings
- Improved documentation with clearer error handling examples

## [0.1.0] - 2025-07-12

### Added
- Initial release of Langfuse Ruby SDK
- Complete tracing capabilities with traces, spans, and generations
- Prompt management with versioning and caching
- Built-in evaluators (exact match, similarity, length, contains, regex)
- Custom scoring and evaluation pipeline support
- Async event processing with automatic batching
- Comprehensive error handling and validation
- Framework integration examples (Rails, Sidekiq)
- Full test suite with RSpec
- Documentation and examples

### Features
- **Tracing**: Full observability for LLM applications
- **Prompt Management**: Version control and deployment of prompts
- **Evaluation**: Multiple built-in evaluators and custom scoring
- **Async Processing**: Background event processing with batching
- **Type Safety**: Comprehensive error handling
- **Integration**: Easy integration with Ruby frameworks 