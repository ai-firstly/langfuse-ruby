# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

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