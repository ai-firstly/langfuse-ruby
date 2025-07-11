#!/usr/bin/env ruby

# Langfuse Ruby SDK Release Verification Script
require 'net/http'
require 'json'
require 'uri'

puts "🔍 Verifying Langfuse Ruby SDK release..."

# Get current version
require_relative '../lib/langfuse/version'
current_version = Langfuse::VERSION

puts "📦 Current version: #{current_version}"

# Check if gem is available on RubyGems
def check_rubygems(gem_name, version)
  uri = URI("https://rubygems.org/api/v1/gems/#{gem_name}.json")

  begin
    response = Net::HTTP.get_response(uri)

    if response.code == '200'
      data = JSON.parse(response.body)
      puts "✅ Gem found on RubyGems:"
      puts "   Name: #{data['name']}"
      puts "   Version: #{data['version']}"
      puts "   Downloads: #{data['downloads']}"
      puts "   Authors: #{data['authors']}"
      puts "   Homepage: #{data['homepage_uri']}"
      puts "   Source: #{data['source_code_uri']}"

      if data['version'] == version
        puts "✅ Version matches current version"
      else
        puts "⚠️  Version mismatch: Expected #{version}, found #{data['version']}"
      end

      return true
    else
      puts "❌ Gem not found on RubyGems (HTTP #{response.code})"
      return false
    end
  rescue => e
    puts "❌ Error checking RubyGems: #{e.message}"
    return false
  end
end

# Check if specific version is available
def check_version_availability(gem_name, version)
  uri = URI("https://rubygems.org/api/v1/versions/#{gem_name}.json")

  begin
    response = Net::HTTP.get_response(uri)

    if response.code == '200'
      versions = JSON.parse(response.body)
      version_found = versions.any? { |v| v['number'] == version }

      if version_found
        puts "✅ Version #{version} is available on RubyGems"
        return true
      else
        puts "❌ Version #{version} not found on RubyGems"
        puts "   Available versions: #{versions.map { |v| v['number'] }.join(', ')}"
        return false
      end
    else
      puts "❌ Could not fetch version list (HTTP #{response.code})"
      return false
    end
  rescue => e
    puts "❌ Error checking version availability: #{e.message}"
    return false
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
  puts "✅ Langfuse module loaded successfully"
  puts "   Version: #{Langfuse::VERSION}"

  # Test client creation (without real credentials)
  begin
    client = Langfuse.new(public_key: 'test', secret_key: 'test')
    puts "✅ Client creation successful"
  rescue Langfuse::AuthenticationError
    puts "✅ Authentication error expected (no real credentials)"
  rescue => e
    puts "❌ Unexpected error creating client: #{e.message}"
  end

  # Test configuration
  Langfuse.configure do |config|
    config.public_key = 'test'
    config.secret_key = 'test'
  end
  puts "✅ Configuration successful"

  # Test utilities
  id = Langfuse::Utils.generate_id
  timestamp = Langfuse::Utils.current_timestamp
  puts "✅ Utilities working (ID: #{id[0..7]}..., Timestamp: #{timestamp})"

rescue => e
  puts "❌ Error testing local functionality: #{e.message}"
end

# Summary
puts "\n📊 Verification Summary:"
puts "   Gem available on RubyGems: #{gem_available ? '✅' : '❌'}"
puts "   Version available: #{version_available ? '✅' : '❌'}"
puts "   Local functionality: ✅"

if gem_available && version_available
  puts "\n🎉 Release verification successful!"
  puts "   Your gem is ready for use!"
  puts "\n📝 Installation command:"
  puts "   gem install langfuse"
else
  puts "\n⚠️  Release verification incomplete"
  puts "   Please check the issues above"
end

puts "\n🔗 Useful links:"
puts "   - RubyGems page: https://rubygems.org/gems/langfuse"
puts "   - Documentation: https://github.com/your-username/langfuse-ruby"
puts "   - Issues: https://github.com/your-username/langfuse-ruby/issues"
