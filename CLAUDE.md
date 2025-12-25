# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

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