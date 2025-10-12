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

### Setup and Installation
```bash
# Initialize development environment
make setup

# Install dependencies manually
make install
# or
bundle install
```

### Testing
```bash
# Run RSpec tests
make test
# or
rake spec
# or
bundle exec rspec

# Run quick tests (without coverage)
make quick-test

# Run tests with coverage report
make test-coverage

# Note: The Makefile references test_offline.rb but this file doesn't exist.
# Use RSpec tests instead, which include both online and offline test scenarios via spec/support/offline_mode_helper.rb
rake test_all
```

### Building and Releasing
```bash
# Build the gem
make build
# or
gem build langfuse-ruby.gemspec

# Install locally
make install-local
# or
gem install pkg/langfuse-ruby-*.gem

# Release to RubyGems (requires permissions)
make release
# or
rake release_gem
```

### Code Quality and Development
```bash
# Run RuboCop linting
make lint
# or
bundle exec rubocop

# Auto-fix RuboCop issues
make lint-fix
# or
bundle exec rubocop -a

# Format code (alias for lint-fix)
make format

# Run all checks (lint + test)
make check

# Generate documentation
make docs
# or
bundle exec yard

# Start documentation server
make docs-serve

# Start IRB console with gem loaded
make console
# or
bundle exec irb -I lib -r langfuse

# Show project status
make status

# Show version info
make version
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
- **Offline Test Helper**: `spec/support/offline_mode_helper.rb` provides utilities for testing without API keys
- **CI/CD**: GitHub Actions workflow tests across Ruby 2.7-3.3
- **VCR**: Uses VCR for HTTP request mocking in tests
- **Test Coverage**: Run `make test-coverage` for detailed coverage reports

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

## Project Structure Tips

- **Makefile**: The primary interface for development tasks - use `make help` to see all available commands
- **Configuration**: Supports environment variables, global config via `Langfuse.configure`, and per-instance options
- **Error Handling**: Comprehensive error hierarchy in `lib/langfuse/errors.rb` with specific exception types
- **Debugging**: Enable debug mode via `debug: true` or `LANGFUSE_DEBUG=true` environment variable
- **Background Processing**: Events are queued and flushed automatically; use `auto_flush: false` for manual control
- **Thread Safety**: Uses concurrent-ruby for thread-safe event queuing and processing
