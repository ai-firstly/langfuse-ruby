# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-01-09

### Added
- Initial release of Langfuse Ruby SDK
- Complete tracing functionality with traces, spans, and generations
- Prompt management with version control and caching
- Built-in evaluation system with multiple evaluators
- Comprehensive error handling and validation
- Automatic event batching and background processing
- Support for environment variable configuration
- Extensive documentation and examples
- Full test coverage with RSpec
- Framework integration examples (Rails, Sidekiq)

### Features
- **Tracing**: Create and manage traces with nested spans and generations
- **Prompt Management**: Create, retrieve, and compile prompts with variable substitution
- **Evaluation**: Built-in evaluators for exact match, similarity, length, regex, and custom scoring
- **Client Management**: Robust HTTP client with retries, timeouts, and authentication
- **Event Processing**: Asynchronous event queue with automatic flushing
- **Error Handling**: Comprehensive error types with detailed messages
- **Utilities**: Helper methods for ID generation, timestamps, and data transformation

### Dependencies
- faraday (~> 2.0) - HTTP client library
- faraday-net_http (~> 3.0) - Net::HTTP adapter for Faraday
- json (~> 2.0) - JSON parsing and generation
- concurrent-ruby (~> 1.0) - Thread-safe data structures

### Development Dependencies
- bundler (~> 2.0)
- rake (~> 13.0)
- rspec (~> 3.0)
- webmock (~> 3.0)
- vcr (~> 6.0)
- rubocop (~> 1.0)
- yard (~> 0.9)

[Unreleased]: https://github.com/your-username/langfuse-ruby/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/your-username/langfuse-ruby/releases/tag/v0.1.0 