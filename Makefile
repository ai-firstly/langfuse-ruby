.PHONY: install test spec test-offline test-all lint lint-fix build release clean console help tag

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies
	bundle install

spec: ## Run RSpec tests
	bundle exec rake spec

test-offline: ## Run offline tests (no network required)
	bundle exec rake test_offline

test-all: ## Run all tests (spec + offline)
	bundle exec rake test_all

test: spec ## Alias for spec

lint: ## Run RuboCop linter
	bundle exec rubocop

lint-fix: ## Run RuboCop with auto-correct
	bundle exec rubocop -A

build: ## Build the gem
	bundle exec rake build

release: tag build ## Release: tag + build + push to RubyGems
	bundle exec rake release_gem

clean: ## Remove built gem files
	rm -f langfuse-ruby-*.gem
	rm -rf pkg/

console: ## Start an IRB console with the gem loaded
	bundle exec irb -r langfuse

tag: ## Create and push a version tag. Usage: make tag [VERSION=x.y.z]
	@git fetch --tags; \
	if [ -z "$(VERSION)" ]; then \
		LATEST=$$(git tag -l 'v*' --sort=-v:refname | head -n1); \
		if [ -z "$$LATEST" ]; then \
			NEW_TAG="v0.0.1"; \
		else \
			MAJOR=$$(echo $$LATEST | sed 's/^v//' | cut -d. -f1); \
			MINOR=$$(echo $$LATEST | sed 's/^v//' | cut -d. -f2); \
			PATCH=$$(echo $$LATEST | sed 's/^v//' | cut -d. -f3); \
			PATCH=$$((PATCH + 1)); \
			NEW_TAG="v$$MAJOR.$$MINOR.$$PATCH"; \
		fi; \
	else \
		NEW_TAG="v$(VERSION)"; \
		LATEST=$$(git tag -l 'v*' --sort=-v:refname | head -n1); \
		if [ "$$LATEST" = "$$NEW_TAG" ]; then \
			echo "Tag $$NEW_TAG already exists on remote, deleting and re-pushing..."; \
			git tag -d "$$NEW_TAG" 2>/dev/null || true; \
			git push origin --delete "$$NEW_TAG" 2>/dev/null || true; \
		elif git tag -l "$$NEW_TAG" | grep -q "$$NEW_TAG"; then \
			echo "Error: Tag $$NEW_TAG exists but is not the latest tag (latest: $$LATEST). Aborting."; \
			exit 1; \
		fi; \
	fi; \
	NEW_VERSION=$$(echo $$NEW_TAG | sed 's/^v//'); \
	echo "Updating version to $$NEW_VERSION ..."; \
	sed -i '' "s/VERSION = '.*'/VERSION = '$$NEW_VERSION'/" lib/langfuse/version.rb; \
	git add lib/langfuse/version.rb; \
	git commit -m "Release $$NEW_TAG" --allow-empty; \
	git tag "$$NEW_TAG"; \
	echo "Pushing tag $$NEW_TAG ..."; \
	git push origin HEAD; \
	git push origin "$$NEW_TAG"; \
	echo "Done! Tagged and pushed $$NEW_TAG"
