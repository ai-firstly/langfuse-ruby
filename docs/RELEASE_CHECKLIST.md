# Langfuse Ruby SDK 发布检查清单

## 发布前

- [ ] `bundle exec rspec`
- [ ] `bundle exec ruby scripts/test_offline.rb`
- [ ] `bundle exec rubocop`
- [ ] README / [V4.md](V4.md) / 示例与代码一致
- [ ] `lib/langfuse/version.rb`
- [ ] `CHANGELOG.md`（Unreleased → 新版本）
- [ ] `bundle install` 更新 `Gemfile.lock`

## 发布

推荐：推送 `vX.Y.Z` tag，由 `.github/workflows/release.yml` 发布。

```bash
git push origin HEAD
git tag vX.Y.Z
git push origin vX.Y.Z
```

需要仓库 secret：`RUBYGEMS_API_KEY`。

本地：

```bash
gem build langfuse-ruby.gemspec
gem push langfuse-ruby-X.Y.Z.gem
```

## 发布后

- [ ] https://rubygems.org/gems/langfuse-ruby 版本正确
- [ ] `gem install langfuse-ruby && ruby -e "require 'langfuse'; puts Langfuse::VERSION"`
- [ ] GitHub Release 已创建
