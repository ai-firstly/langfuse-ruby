#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates URL encoding for prompt names with special characters
# such as forward slashes, spaces, and other URL-unsafe characters.

require_relative '../lib/langfuse'

# Initialize the Langfuse client
client = Langfuse::Client.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'] || 'your-public-key',
  secret_key: ENV['LANGFUSE_SECRET_KEY'] || 'your-secret-key',
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

# Example 1: Prompt name with forward slash
# Before fix: Would result in 404 error
# After fix: Automatically URL-encoded to EXEMPLE%2Fmy-prompt
puts 'Example 1: Fetching prompt with forward slash in name'
begin
  prompt = client.get_prompt('EXEMPLE/my-prompt')
  puts "✓ Successfully fetched prompt: #{prompt.name}"
rescue Langfuse::ValidationError => e
  puts "✗ Error: #{e.message}"
end

# Example 2: Prompt name with spaces
puts "\nExample 2: Fetching prompt with spaces in name"
begin
  prompt = client.get_prompt('my prompt name')
  puts "✓ Successfully fetched prompt: #{prompt.name}"
rescue Langfuse::ValidationError => e
  puts "✗ Error: #{e.message}"
end

# Example 3: Prompt name with multiple special characters
puts "\nExample 3: Fetching prompt with multiple special characters"
begin
  prompt = client.get_prompt('test/prompt name?query')
  puts "✓ Successfully fetched prompt: #{prompt.name}"
rescue Langfuse::ValidationError => e
  puts "✗ Error: #{e.message}"
end

# Example 4: Simple prompt name (no special characters)
puts "\nExample 4: Fetching prompt with simple name"
begin
  prompt = client.get_prompt('simple-prompt')
  puts "✓ Successfully fetched prompt: #{prompt.name}"
rescue Langfuse::ValidationError => e
  puts "✗ Error: #{e.message}"
end

puts "\n" + '=' * 60
puts 'Note: The client now automatically URL-encodes prompt names.'
puts 'You no longer need to manually encode them!'
puts '=' * 60
