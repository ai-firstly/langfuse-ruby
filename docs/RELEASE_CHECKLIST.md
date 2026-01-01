# Langfuse Ruby SDK 发布检查清单

## 📋 发布前检查

### 1. 代码质量检查
- [ ] 所有测试通过 (`bundle exec rspec`)
- [ ] 离线测试通过 (`ruby scripts/test_offline.rb`)
- [ ] 代码风格检查 (`bundle exec rubocop`)
- [ ] 文档更新完成

### 2. 版本管理
- [ ] 更新版本号 (`lib/langfuse/version.rb`)
- [ ] 更新变更日志 (`CHANGELOG.md`)
- [ ] 更新 README 如有必要

### 3. 个人信息更新
- [ ] 更新 `langfuse.gemspec` 中的作者信息
- [ ] 更新 GitHub 仓库链接
- [ ] 更新邮箱地址

### 4. Git 仓库设置
- [ ] 初始化 Git 仓库 (`git init`)
- [ ] 添加远程仓库
- [ ] 提交所有更改
- [ ] 推送到 GitHub

## 🚀 发布步骤

### 方法 1: 使用发布脚本 (推荐)
```bash
./scripts/release.sh
```

### 方法 2: 手动发布
```bash
# 1. 运行测试
bundle exec rspec
ruby scripts/test_offline.rb

# 2. 构建 gem
gem build langfuse.gemspec

# 3. 发布到 RubyGems
gem push langfuse-ruby-0.1.0.gem

# 4. 创建 Git 标签
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

### 方法 3: 使用 GitHub Actions
1. 推送代码到 GitHub
2. 创建版本标签 (`git tag v0.1.0 && git push origin v0.1.0`)
3. GitHub Actions 自动发布

## 📊 发布后验证

### 1. 检查 RubyGems
- [ ] 访问 https://rubygems.org/gems/langfuse
- [ ] 确认版本号正确
- [ ] 检查下载链接

### 2. 测试安装
```bash
# 从 RubyGems 安装
gem install langfuse-ruby

# 测试基本功能
ruby -e "require 'langfuse'; puts Langfuse::VERSION"
```

### 3. 更新文档
- [ ] 更新 README 中的安装说明
- [ ] 更新项目网站（如有）
- [ ] 发布公告

## 🔧 常见问题解决

### RubyGems 认证问题
```bash
# 登录 RubyGems
gem signin

# 或设置 API 密钥
gem signin --key your_api_key
```

### Git 标签问题
```bash
# 删除本地标签
git tag -d v0.1.0

# 删除远程标签
git push origin --delete v0.1.0

# 重新创建标签
git tag v0.1.0
git push origin v0.1.0
```

### 版本冲突
```bash
# 检查现有版本
gem search langfuse

# 更新版本号后重新发布
# 编辑 lib/langfuse/version.rb
# 重新构建和发布
```

## 📞 获取帮助

如果遇到问题：
1. 查看 RubyGems 文档
2. 检查 GitHub Issues
3. 联系 Ruby 社区
4. 参考其他成功的 gem 项目

## 🎉 发布成功后

1. 🎊 庆祝！您的 gem 已成功发布
2. 📢 在社交媒体上分享
3. 📝 写博客文章介绍
4. 🔗 联系 Langfuse 团队添加到官方文档
5. 📈 监控使用情况和反馈

---

**记住：发布是一个里程碑，但维护才是长期的工作！** 