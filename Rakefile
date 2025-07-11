require "bundler/gem_tasks"
require "rspec/core/rake_task"
require_relative "lib/langfuse/version"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

# Custom release task
desc "Release gem to RubyGems"
task :release_gem => [:build] do
  sh "gem push pkg/langfuse-#{Langfuse::VERSION}.gem"
end

# Offline test task
desc "Run offline tests"
task :test_offline do
  sh "ruby test_offline.rb"
end

# Complete test suite
desc "Run all tests"
task :test_all => [:spec, :test_offline]
