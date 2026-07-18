# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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