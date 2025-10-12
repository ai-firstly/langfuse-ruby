# Langfuse Ruby SDK Makefile
# 提供常用的开发任务快捷命令

.PHONY: help install test test-all test-offline lint clean build install-local release docs console format check

# 默认目标
.DEFAULT_GOAL := help

# 颜色定义
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# Ruby 版本检查
RUBY_VERSION := $(shell ruby -e 'puts RUBY_VERSION')
REQUIRED_RUBY_VERSION := 2.7.0

# 版本信息
VERSION := $(shell ruby -I lib -e 'require "langfuse/version"; puts Langfuse::VERSION')

help: ## 显示帮助信息
	@echo "$(BLUE)Langfuse Ruby SDK 开发任务$(RESET)"
	@echo ""
	@echo "$(GREEN)可用命令:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-15s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(BLUE)当前信息:$(RESET)"
	@echo "  Ruby 版本: $(RUBY_VERSION) (需要 >= $(REQUIRED_RUBY_VERSION))"
	@echo "  Gem 版本: $(VERSION)"

check-ruby: ## 检查 Ruby 版本
	@echo "$(BLUE)检查 Ruby 版本...$(RESET)"
	@ruby -e "exit if RUBY_VERSION >= '$(REQUIRED_RUBY_VERSION)'; puts '$(RED)错误: 需要 Ruby >= $(REQUIRED_RUBY_VERSION)，当前版本: ' + RUBY_VERSION; exit 1"

install: check-ruby ## 安装依赖
	@echo "$(BLUE)安装依赖...$(RESET)"
	@bundle install

test: ## 运行 RSpec 测试
	@echo "$(BLUE)运行 RSpec 测试...$(RESET)"
	@bundle exec rspec

test-offline: ## 运行离线测试
	@echo "$(BLUE)运行离线测试...$(RESET)"
	@ruby test_offline.rb

test-all: test test-offline ## 运行所有测试

test-coverage: ## 运行测试并生成覆盖率报告
	@echo "$(BLUE)运行测试并生成覆盖率报告...$(RESET)"
	@bundle exec rspec --format documentation

lint: ## 运行 RuboCop 代码检查
	@echo "$(BLUE)运行 RuboCop 代码检查...$(RESET)"
	@bundle exec rubocop

lint-fix: ## 自动修复 RuboCop 问题
	@echo "$(BLUE)自动修复 RuboCop 问题...$(RESET)"
	@bundle exec rubocop -a

format: lint-fix ## 格式化代码（别名）

check: lint test ## 运行所有检查（代码检查 + 测试）

clean: ## 清理临时文件
	@echo "$(BLUE)清理临时文件...$(RESET)"
	@rm -rf pkg/
	@rm -rf coverage/
	@rm -rf .rspec_status/
	@find . -name "*.gem" -delete
	@find . -name ".DS_Store" -delete

build: clean ## 构建 gem
	@echo "$(BLUE)构建 gem...$(RESET)"
	@gem build langfuse-ruby.gemspec
	@mkdir -p pkg/
	@mv langfuse-ruby-*.gem pkg/

install-local: build ## 本地安装构建的 gem
	@echo "$(BLUE)本地安装 gem...$(RESET)"
	@gem install pkg/langfuse-ruby-$(VERSION).gem

release: clean check ## 发布 gem 到 RubyGems (需要权限)
	@echo "$(BLUE)发布 gem 到 RubyGems...$(RESET)"
	@rake release_gem

docs: ## 生成文档
	@echo "$(BLUE)生成文档...$(RESET)"
	@bundle exec yard

docs-serve: ## 启动文档服务器
	@echo "$(BLUE)启动文档服务器...$(RESET)"
	@bundle exec yard server --reload

console: ## 启动 IRB 控制台并加载 gem
	@echo "$(BLUE)启动 IRB 控制台...$(RESET)"
	@bundle exec irb -I lib -r langfuse

version: ## 显示版本信息
	@echo "$(GREEN)当前版本: $(VERSION)$(RESET)"

status: ## 显示项目状态
	@echo "$(BLUE)项目状态:$(RESET)"
	@echo "  Git 分支: $(shell git branch --show-current 2>/dev/null || echo 'N/A')"
	@echo "  Git 状态: $(shell git status --porcelain 2>/dev/null | wc -l | tr -d ' ') 个修改"
	@echo "  最后提交: $(shell git log -1 --pretty=format:'%h %s' 2>/dev/null || echo 'N/A')"

setup: install ## 初始化开发环境
	@echo "$(GREEN)开发环境初始化完成！$(RESET)"
	@echo ""
	@echo "$(YELLOW)下一步:$(RESET)"
	@echo "  make test     # 运行测试"
	@echo "  make lint     # 检查代码"
	@echo "  make console  # 启动控制台"

ci: lint test-all ## CI 流水线任务

# 开发辅助任务
watch-test: ## 监控文件变化并自动运行测试
	@echo "$(BLUE)监控文件变化并运行测试...$(RESET)"
	@bundle exec guard start

quick-test: ## 快速测试（不包含覆盖率）
	@echo "$(BLUE)快速测试...$(RESET)"
	@bundle exec rspec --format progress

# 示例相关
run-examples: ## 运行所有示例
	@echo "$(BLUE)运行示例...$(RESET)"
	@for file in examples/*.rb; do \
		echo "$(YELLOW)运行 $$file$(RESET)"; \
		ruby "$$file" || true; \
		done

# 安全检查
security-check: ## 检查依赖安全性
	@echo "$(BLUE)检查依赖安全性...$(RESET)"
	@bundle audit

# 性能测试
benchmark: ## 运行性能测试
	@echo "$(BLUE)运行性能测试...$(RESET)"
	@if [ -f "spec/benchmark" ]; then \
		cd spec/benchmark && ruby *.rb; \
	else \
		echo "$(YELLOW)没有找到性能测试文件$(RESET)"; \
	fi

# 更新依赖
update-deps: ## 更新依赖
	@echo "$(BLUE)更新依赖...$(RESET)"
	@bundle update
	@make test

# 清理并重新安装
reinstall: clean install ## 清理并重新安装

# 显示环境信息
env: ## 显示开发环境信息
	@echo "$(BLUE)开发环境信息:$(RESET)"
	@echo "  Ruby: $(RUBY_VERSION)"
	@echo "  Bundler: $(shell bundle --version)"
	@echo "  Git: $(shell git --version)"
	@echo "  系统: $(shell uname -s)"
	@echo "  架构: $(shell uname -m)"