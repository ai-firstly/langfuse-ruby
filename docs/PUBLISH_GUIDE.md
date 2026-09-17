# Langfuse Ruby SDK 发布指南

Gem 名称是 **`langfuse-ruby`**（gemspec：`langfuse-ruby.gemspec`）。推送 `v*` tag 会走 GitHub Actions 自动发到 RubyGems。

## 常规发布（推荐）

仓库 **Settings → Secrets and variables → Actions** 需要 `RUBYGEMS_API_KEY`。

```bash
# 1. 改版本
#    lib/langfuse/version.rb
#    CHANGELOG.md（把 Unreleased 收成新版本）
#    bundle install   # 同步 Gemfile.lock 里的 gem 版本

# 2. 测试
bundle exec rake spec
bundle exec ruby scripts/test_offline.rb
bundle exec rubocop

# 3. 提交、推送、打 tag（tag 触发 release.yml）
git add -A
git commit -m "Release vX.Y.Z"
git push origin HEAD
git tag vX.Y.Z
git push origin vX.Y.Z
```

Actions 会：跑 rspec + offline tests → `gem build langfuse-ruby.gemspec` → `gem push` → 创建 GitHub Release。

也可用：

```bash
make tag VERSION=X.Y.Z
```

（会改 `version.rb`、提交、打 tag 并 push。文档和 CHANGELOG 请事先改好。）

## 本地手动发

```bash
bundle exec rspec
bundle exec ruby scripts/test_offline.rb
gem build langfuse-ruby.gemspec
gem push langfuse-ruby-X.Y.Z.gem
git tag vX.Y.Z
git push origin HEAD
git push origin vX.Y.Z
```

需要已登录 RubyGems（`gem signin` 或 `~/.gem/credentials`）。

## 发完核对

- https://rubygems.org/gems/langfuse-ruby
- `gem install langfuse-ruby` 后 `ruby -e "require 'langfuse'; puts Langfuse::VERSION"`
- `ruby scripts/verify_release.rb`

## 撤回

```bash
gem yank langfuse-ruby -v X.Y.Z
```

只能 yank，不能改已发布版本的元数据。
