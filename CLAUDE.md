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

- **`Langfuse::Client`** ([lib/langfuse/client.rb](lib/langfuse/client.rb)) - Main entry point. Handles API authentication, HTTP connections (via Faraday), event queuing with `Concurrent::Array`, and background flush thread for auto-batching events.

- **`Langfuse::Trace`** ([lib/langfuse/trace.rb](lib/langfuse/trace.rb)) - Top-level container for a request/session. Creates child observations (spans, generations, events) and supports scoring.

- **`Langfuse::Span`** ([lib/langfuse/span.rb](lib/langfuse/span.rb)) - Represents a timed operation. Supports enhanced observation types via `as_type` parameter (agent, tool, chain, retriever, embedding, evaluator, guardrail).

- **`Langfuse::Generation`** ([lib/langfuse/generation.rb](lib/langfuse/generation.rb)) - LLM call tracking with model, usage, and cost data.

- **`Langfuse::Event`** ([lib/langfuse/event.rb](lib/langfuse/event.rb)) - Generic point-in-time events for logging.

- **`Langfuse::Prompt`** ([lib/langfuse/prompt.rb](lib/langfuse/prompt.rb)) - Prompt templates with variable compilation and caching.

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

## Key Implementation Details

- Uses Faraday for HTTP with Basic Auth (public_key:secret_key)
- Prompt names with special characters are auto-URL-encoded via `Utils.url_encode`
- `trace-update` events merge into existing `trace-create` in queue (deduplication)
- All keys are converted to camelCase before API submission via `Utils.deep_camelize_keys`
This is the **Langfuse Ruby SDK** - a Ruby client library for Langfuse, an open-source LLM engineering platform. The SDK provides tracing, prompt management, evaluation, and event tracking capabilities for LLM applications.

## Common Development Commands

### Testing
```bash
# Run all tests
rake spec
# or
bundle exec rspec

# Run offline tests (additional test suite)
ruby test_offline.rb

# Run complete test suite (both online and offline)
rake test_all
```

### Building and Releasing
```bash
# Build the gem
gem build langfuse-ruby.gemspec

# Install locally
gem install langfuse-ruby-*.gem

# Release to RubyGems (requires permissions)
rake release_gem
```

### Code Quality
```bash
# Run RuboCop linting
bundle exec rubocop

# Generate documentation
bundle exec yard
```

## Architecture Overview

### Core Components

The SDK follows a modular architecture with these main components:

- **Client** (`lib/langfuse/client.rb`): Main entry point, handles HTTP communication, event queuing, and background processing
- **Trace** (`lib/langfuse/trace.rb`): Top-level tracing container for LLM operations
- **Span** (`lib/langfuse/span.rb`): Nested operations within traces
- **Generation** (`lib/langfuse/generation.rb`): LLM model calls with input/output tracking
- **Event** (`lib/langfuse/event.rb`): Generic event tracking for custom application events
- **Prompt** (`lib/langfuse/prompt.rb`): Prompt management and template functionality
- **Evaluation** (`lib/langfuse/evaluation.rb`): Built-in evaluators and scoring capabilities
- **Utils** (`lib/langfuse/utils.rb`): Common utilities for ID generation and timestamps
- **Errors** (`lib/langfuse/errors.rb`): Custom exception classes

### Key Design Patterns

1. **Fluent Interface**: All tracing objects support method chaining for easy composition
2. **Background Processing**: Uses concurrent-ruby for automatic event flushing in background threads
3. **Flexible Configuration**: Supports environment variables, global configuration, and per-instance settings
4. **Error Handling**: Comprehensive error hierarchy for different failure modes

### Data Flow

1. Events are created through Client methods (trace, span, generation, event)
2. Events are queued in memory (`Concurrent::Array`)
3. Background thread periodically flushes events to Langfuse API
4. Manual flushing available via `client.flush`

## Configuration

The SDK supports multiple configuration methods:

1. **Environment Variables**: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`, etc.
2. **Global Configuration**: `Langfuse.configure { |config| ... }`
3. **Per-Instance**: `Langfuse.new(public_key: ..., secret_key: ...)`

Key configuration options:
- `auto_flush`: Enable/disable automatic background flushing (default: true)
- `flush_interval`: Background flush interval in seconds (default: 5)
- `timeout`: HTTP request timeout (default: 30)
- `retries`: Number of retry attempts (default: 3)

## Testing Strategy

- **RSpec tests**: Unit and integration tests in `spec/` directory
- **Offline tests**: Additional tests in `test_offline.rb` that don't require API keys
- **CI/CD**: GitHub Actions workflow tests across Ruby 2.7-3.3
- **VCR**: Uses VCR for HTTP request mocking in tests

## Examples

The `examples/` directory contains comprehensive usage examples:
- `basic_tracing.rb`: Basic trace and generation usage
- `prompt_management.rb`: Prompt creation and template usage
- `event_usage.rb`: Event tracking examples
- `auto_flush_control.rb`: Flushing behavior configuration
- `connection_config_demo.rb`: Network configuration examples

## Dependencies

Core runtime dependencies:
- `concurrent-ruby`: Thread-safe data structures and concurrent processing
- `faraday`: HTTP client with configurable middleware
- `faraday-net_http`: HTTP adapter
- `faraday-multipart`: Multipart request support
- `json`: JSON parsing and generation

Development dependencies include RSpec, RuboCop, YARD, VCR, and WebMock for testing and documentation.

## Version Management

Version is defined in `lib/langfuse/version.rb` and follows semantic versioning. The project supports Ruby >= 2.7.0.
