# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0]

### Added

- Added `return_with_context/2` and `return_with_context/3` functions to return pipeline results along with context

### Changed

- Enhanced test suite with additional edge cases for error handling and context management

## [0.3.1]

### Changed

- Added timeout option to `await/2` function for handling long-running tasks

## [0.3.0]

### Added

- Added asynchronous pipeline execution with `async/2` and `async/3` functions
- Added `await/1` function to wait for all pending async tasks to complete
- Added Task.Supervisor for managing async step execution
- Added Application behavior to Extep for proper supervision tree

### Changed

- Enhanced Extep struct with `tasks` field to track pending async operations
- Updated `run/2` and `run/3` to automatically await pending tasks before execution
- Updated `return/2` and `return/3` to handle pending tasks before returning results
- Enhanced error handling to properly shut down tasks when pipeline is interrupted
- Improved function guards and type specifications for better pattern matching

### Technical Details

- The `async/2` function runs checker functions asynchronously without modifying context
- The `async/3` function runs mutator functions asynchronously and stores results under given keys
- All async tasks are executed in parallel and results are merged in order when `await/1` is called
- Pipeline stops at first async task failure, with proper task cleanup
- Backward compatibility maintained - existing synchronous pipelines work unchanged

## [0.2.0]

### Added

- Added `label_error` option to `return/3` for better error debugging and identification
- Added extensive test coverage for `label_error` functionality

### Changed

- Improved `run/2` documentation with clearer explanations of:
  - Function return values and their effects
  - Error message labeling for named vs anonymous functions
  - Pipeline behavior and when functions execute
- Improved `run/3` documentation with detailed explanations of:
  - Parameter requirements and usage
  - Context mutation behavior
  - Error scenarios with step-by-step breakdowns
  - Halt scenarios and pipeline flow control
- Enhanced `return/3` documentation with comprehensive examples covering:
  - Successful pipeline scenarios
  - Error handling with and without labels
  - Halt message handling
  - Different error labeling behaviors
- Improved README.md API documentation with `label_error` usage examples

## [0.1.0] - Previous Release

### Added

- Initial implementation of Extep pipeline runner
- Core functions: `new/0`, `new/1`, `run/2`, `run/3`, `return/2`
- Basic error handling and pipeline flow control
- Railway-oriented programming pattern implementation
