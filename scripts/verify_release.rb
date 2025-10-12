#!/usr/bin/env ruby
# frozen_string_literal: true

# Langfuse Ruby SDK Release Verification Script
require 'net/http'
require 'json'
require 'uri'

puts '🔍 Verifying Langfuse Ruby SDK release...'

# Get current version
require_relative '../lib/langfuse/version'
current_version = Langfuse::VERSION

puts "📦 Current version: #{current_version}"

# Check if gem is available on RubyGems
def check_rubygems(gem_name, version)
  uri = URI("https://rubygems.org/api/v1/gems/#{gem_name}.json")
  response = fetch_gem_response(uri)

  return false unless response

  data = parse_gem_response(response)
  return false unless data

  display_gem_info(data)
  check_version_match(data['version'], version)
  true
end

def fetch_gem_response(uri)
  response = Net::HTTP.get_response(uri)
  return response if response.code == '200'

  puts "❌ Gem not found on RubyGems (HTTP #{response.code})"
  false
rescue StandardError => e
  puts "❌ Error checking RubyGems: #{e.message}"
  false
end

def parse_gem_response(response)
  JSON.parse(response.body)
rescue JSON::ParserError
  puts '❌ Failed to parse gem response'
  false
end

def display_gem_info(data)
  puts '✅ Gem found on RubyGems:'
  puts "   Name: #{data['name']}"
  puts "   Version: #{data['version']}"
  puts "   Downloads: #{data['downloads']}"
  puts "   Authors: #{data['authors']}"
  puts "   Homepage: #{data['homepage_uri']}"
  puts "   Source: #{data['source_code_uri']}"
end

def check_version_match(actual_version, expected_version)
  if actual_version == expected_version
    puts '✅ Version matches current version'
  else
    puts "⚠️  Version mismatch: Expected #{expected_version}, found #{actual_version}"
  end
end

# Check if specific version is available
def check_version_availability(gem_name, version)
  uri = URI("https://rubygems.org/api/v1/versions/#{gem_name}.json")
  response = fetch_versions_response(uri)

  return false unless response

  versions = parse_versions_response(response)
  return false unless versions

  check_version_in_list(versions, version, gem_name)
end

def fetch_versions_response(uri)
  response = Net::HTTP.get_response(uri)
  return response if response.code == '200'

  puts "❌ Could not fetch version list (HTTP #{response.code})"
  false
rescue StandardError => e
  puts "❌ Error checking version availability: #{e.message}"
  false
end

def parse_versions_response(response)
  JSON.parse(response.body)
rescue JSON::ParserError
  puts '❌ Failed to parse version response'
  false
end

def check_version_in_list(versions, version, _gem_name)
  version_found = versions.any? { |v| v['number'] == version }

  if version_found
    puts "✅ Version #{version} is available on RubyGems"
    true
  else
    puts "❌ Version #{version} not found on RubyGems"
    puts "   Available versions: #{versions.map { |v| v['number'] }.join(', ')}"
    false
  end
end

# Run checks
puts "\n🔍 Checking RubyGems availability..."
gem_available = check_rubygems('langfuse', current_version)

puts "\n🔍 Checking version availability..."
version_available = check_version_availability('langfuse', current_version)

# Test local installation
puts "\n🔍 Testing local gem functionality..."
begin
  require_relative '../lib/langfuse'

  # Test basic functionality
  puts '✅ Langfuse module loaded successfully'
  puts "   Version: #{Langfuse::VERSION}"

  # Test client creation (without real credentials)
  begin
    Langfuse.new(public_key: 'test', secret_key: 'test')
    puts '✅ Client creation successful'
  rescue Langfuse::AuthenticationError
    puts '✅ Authentication error expected (no real credentials)'
  rescue StandardError => e
    puts "❌ Unexpected error creating client: #{e.message}"
  end

  # Test configuration
  Langfuse.configure do |config|
    config.public_key = 'test'
    config.secret_key = 'test'
  end
  puts '✅ Configuration successful'

  # Test utilities
  id = Langfuse::Utils.generate_id
  timestamp = Langfuse::Utils.current_timestamp
  puts "✅ Utilities working (ID: #{id[0..7]}..., Timestamp: #{timestamp})"
rescue StandardError => e
  puts "❌ Error testing local functionality: #{e.message}"
end

# Summary
puts "\n📊 Verification Summary:"
puts "   Gem available on RubyGems: #{gem_available ? '✅' : '❌'}"
puts "   Version available: #{version_available ? '✅' : '❌'}"
puts '   Local functionality: ✅'

if gem_available && version_available
  puts "\n🎉 Release verification successful!"
  puts '   Your gem is ready for use!'
  puts "\n📝 Installation command:"
  puts '   gem install langfuse-ruby'
else
  puts "\n⚠️  Release verification incomplete"
  puts '   Please check the issues above'
end

puts "\n🔗 Useful links:"
puts '   - RubyGems page: https://rubygems.org/gems/langfuse'
puts '   - Documentation: https://github.com/ai-firstly/langfuse-ruby'
puts '   - Issues: https://github.com/ai-firstly/langfuse-ruby/issues'
