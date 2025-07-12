# Langfuse Ruby SDK 发布指南

本指南将帮助您将 Langfuse Ruby SDK 发布到 RubyGems.org。

## 📋 发布前准备清单

### 1. 更新个人信息

首先，您需要更新 `langfuse.gemspec` 文件中的个人信息：

```ruby
# 在 langfuse.gemspec 中更新以下字段：
spec.authors       = ["Your Real Name"]
spec.email         = ["your.real.email@example.com"]
spec.homepage      = "https://github.com/your-github-username/langfuse-ruby"
spec.metadata["source_code_uri"] = "https://github.com/your-github-username/langfuse-ruby"
spec.metadata["changelog_uri"] = "https://github.com/your-github-username/langfuse-ruby/blob/main/CHANGELOG.md"
```

### 2. 设置 Git 仓库

```bash
# 初始化 Git 仓库
git init

# 添加所有文件
git add .

# 提交初始版本
git commit -m "Initial commit: Langfuse Ruby SDK v0.1.0"

# 添加远程仓库（替换为您的 GitHub 仓库）
git remote add origin https://github.com/ai-firstly/langfuse-ruby.git

# 推送到 GitHub
git push -u origin master
```

### 3. 创建 GitHub 仓库

1. 登录 GitHub
2. 创建新仓库：`langfuse-ruby`
3. 设置为公开仓库
4. 添加 README.md（已存在）
5. 添加 LICENSE（已存在）

## 🔧 发布准备

### 1. 验证 Gem 构建

```bash
# 构建 gem
gem build langfuse-ruby.gemspec

# 检查构建结果
ls -la *.gem
```

### 2. 本地测试安装

```bash
# 本地安装构建的 gem
gem install ./langfuse-ruby-0.1.0.gem

# 测试安装是否成功
ruby -e "require 'langfuse'; puts 'Langfuse loaded successfully'"

# 卸载本地测试版本
gem uninstall langfuse-ruby
```

### 3. 运行完整测试

```bash
# 运行所有测试
bundle exec rspec

# 运行离线测试
ruby test_offline.rb

# 检查代码质量（可选）
bundle exec rubocop
```

## 🚀 发布到 RubyGems

### 1. 注册 RubyGems 账户

如果您还没有 RubyGems 账户：

1. 访问 https://rubygems.org/sign_up
2. 注册新账户
3. 验证邮箱

### 2. 配置 RubyGems 凭据

```bash
# 设置 RubyGems 凭据
gem signin

# 或者手动设置
echo "---" > ~/.gem/credentials
echo ":rubygems_api_key: YOUR_API_KEY" >> ~/.gem/credentials
chmod 0600 ~/.gem/credentials
```

### 3. 发布 Gem

```bash
# 构建最新版本
gem build langfuse-ruby.gemspec

# 发布到 RubyGems
gem push langfuse-ruby-0.1.x.gem
```

## 📊 发布后验证

### 1. 验证发布成功

```bash
# 检查 gem 是否可用
gem search langfuse

# 从 RubyGems 安装
gem install langfuse-ruby

# 测试功能
ruby -e "
require 'langfuse'
puts 'Langfuse version: ' + Langfuse::VERSION
client = Langfuse.new(public_key: 'test', secret_key: 'test')
puts 'Client created successfully'
"
```

### 2. 更新文档

发布后，更新以下文档：

- README.md 中的安装说明
- 项目网站或博客文章
- 社交媒体公告

## 🔄 版本更新流程

### 1. 更新版本号

```ruby
# 在 lib/langfuse/version.rb 中更新版本
module Langfuse
  VERSION = "0.1.1"  # 或新的版本号
end
```

### 2. 更新变更日志

在 `CHANGELOG.md` 中添加新版本的变更：

```markdown
## [0.1.1] - 2025-01-10

### Added
- 新功能描述

### Changed
- 修改内容描述

### Fixed
- 修复问题描述
```

### 3. 提交和标签

```bash
# 提交变更
git add .
git commit -m "Bump version to 0.1.1"

# 创建版本标签
git tag v0.1.1

# 推送到 GitHub
git push origin main
git push origin v0.1.1
```

### 4. 发布新版本

```bash
# 构建新版本
gem build langfuse.gemspec

# 发布到 RubyGems
gem push langfuse-0.1.1.gem
```

## 🛠️ 自动化发布（可选）

### 使用 GitHub Actions

创建 `.github/workflows/release.yml`：

```yaml
name: Release Gem

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.0
          bundler-cache: true
      
      - name: Run tests
        run: bundle exec rspec
      
      - name: Build gem
        run: gem build langfuse.gemspec
      
      - name: Publish to RubyGems
        run: |
          mkdir -p ~/.gem
          echo ":rubygems_api_key: ${{ secrets.RUBYGEMS_API_KEY }}" > ~/.gem/credentials
          chmod 0600 ~/.gem/credentials
          gem push *.gem
```

### 使用 Rake 任务

在 `Rakefile` 中添加：

```ruby
require 'bundler/gem_tasks'

desc "Release gem"
task :release => [:build] do
  sh "gem push pkg/langfuse-#{Langfuse::VERSION}.gem"
end
```

## 📈 推广和维护

### 1. 社区推广

- 在 Ruby 社区论坛发布
- 写博客文章介绍 SDK
- 在相关的 GitHub 仓库中提 PR 添加到集成列表
- 联系 Langfuse 团队，请求添加到官方文档

### 2. 持续维护

- 定期更新依赖项
- 修复用户报告的问题
- 添加新功能
- 保持与 Langfuse API 的兼容性

## 🆘 常见问题

### Q: 发布失败怎么办？

A: 检查以下常见问题：
- 版本号是否已存在
- 凭据是否正确
- 网络连接是否正常
- gemspec 文件是否有语法错误

### Q: 如何撤回已发布的版本？

A: 使用 `gem yank` 命令：

```bash
gem yank langfuse -v 0.1.0
```

### Q: 如何更新 gem 的元数据？

A: 更新 gemspec 文件后发布新版本，旧版本的元数据无法修改。

## 📞 获取帮助

如果在发布过程中遇到问题：

1. 查看 RubyGems 官方文档
2. 检查 GitHub Issues
3. 联系 Ruby 社区
4. 参考其他成功的 gem 项目

---

**祝您发布成功！** 🎉 