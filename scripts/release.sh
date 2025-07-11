#!/bin/bash

# Langfuse Ruby SDK Release Script
set -e

echo "🚀 Starting Langfuse Ruby SDK release process..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    print_error "This is not a git repository. Please run 'git init' first."
    exit 1
fi

# Get current version
CURRENT_VERSION=$(ruby -r ./lib/langfuse/version.rb -e "puts Langfuse::VERSION")
print_status "Current version: $CURRENT_VERSION"

# Check if there are uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    print_warning "You have uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi

# Run tests
print_status "Running tests..."
if ! bundle exec rspec; then
    print_error "Tests failed. Please fix them before releasing."
    exit 1
fi

print_status "Running offline tests..."
if ! ruby test_offline.rb; then
    print_error "Offline tests failed. Please fix them before releasing."
    exit 1
fi

# Build gem
print_status "Building gem..."
if ! gem build langfuse.gemspec; then
    print_error "Gem build failed."
    exit 1
fi

# Check if gem was built successfully
if [ ! -f "langfuse-${CURRENT_VERSION}.gem" ]; then
    print_error "Gem file not found: langfuse-${CURRENT_VERSION}.gem"
    exit 1
fi

print_status "Gem built successfully: langfuse-${CURRENT_VERSION}.gem"

# Ask for confirmation
echo
echo "📋 Release Summary:"
echo "  Version: $CURRENT_VERSION"
echo "  Gem file: langfuse-${CURRENT_VERSION}.gem"
echo "  Tests: ✅ Passed"
echo

read -p "Do you want to proceed with the release? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Release cancelled."
    rm -f "langfuse-${CURRENT_VERSION}.gem"
    exit 0
fi

# Create git tag
print_status "Creating git tag v${CURRENT_VERSION}..."
git tag "v${CURRENT_VERSION}"

# Push to git
print_status "Pushing to git..."
git push origin main
git push origin "v${CURRENT_VERSION}"

# Publish to RubyGems
print_status "Publishing to RubyGems..."
if gem push "langfuse-${CURRENT_VERSION}.gem"; then
    print_status "Successfully published to RubyGems!"
else
    print_error "Failed to publish to RubyGems."
    print_warning "You may need to run 'gem signin' first."
    exit 1
fi

# Clean up
rm -f "langfuse-${CURRENT_VERSION}.gem"

print_status "Release completed successfully! 🎉"
echo
echo "📝 Next steps:"
echo "  1. Check https://rubygems.org/gems/langfuse"
echo "  2. Update documentation if needed"
echo "  3. Announce the release"
echo
echo "🔗 Useful links:"
echo "  - RubyGems: https://rubygems.org/gems/langfuse"
echo "  - GitHub: https://github.com/your-username/langfuse-ruby"
echo "  - Documentation: https://github.com/your-username/langfuse-ruby#readme" 