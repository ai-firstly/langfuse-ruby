# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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