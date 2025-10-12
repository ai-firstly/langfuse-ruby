# Langfuse Ruby SDK 发布指南

本指南将帮助您将 Langfuse Ruby SDK 发布到 RubyGems.org。

## 📋 发布前准备

### 1.1 更新个人信息

更新 `langfuse-ruby.gemspec` 文件中的个人信息：

```ruby
spec.authors       = ["Your Real Name"]
spec.email         = ["your.real.email@example.com"]
spec.homepage      = "https://github.com/your-username/langfuse-ruby"
spec.metadata["source_code_uri"] = "https://github.com/your-username/langfuse-ruby"
spec.metadata["changelog_uri"] = "https://github.com/your-username/langfuse-ruby/blob/main/CHANGELOG.md"
```

### 1.2 版本管理

更新版本号和变更日志：

```bash
# 更新版本号 (lib/langfuse/version.rb)
VERSION = "0.1.1"

# 更新变更日志 (CHANGELOG.md)
# 添加新版本的变更记录
```

### 1.3 代码质量检查

```bash
# 运行所有测试
make test

# 检查代码风格
make lint

# 运行完整检查
make check
```

## 🚀 发布流程

### 2.1 准备 Git 仓库

```bash
# 提交所有更改
git add .
git commit -m "Release v0.1.1"

# 创建版本标签
git tag v0.1.1

# 推送到 GitHub
git push origin main
git push origin v0.1.1
```

### 2.2 构建 Gem

```bash
# 清理并构建
make clean
make build

# 验证构建结果
ls -la pkg/langfuse-ruby-*.gem
```

### 2.3 发布到 RubyGems

```bash
# 方法 1: 使用 Makefile
make release

# 方法 2: 手动发布
gem push pkg/langfuse-ruby-0.1.1.gem
```

## 📊 发布后验证

### 3.1 验证发布成功

```bash
# 检查 gem 是否可用
gem search langfuse-ruby

# 从 RubyGems 安装测试
gem install langfuse-ruby

# 验证功能
ruby -e "
require 'langfuse'
puts 'Langfuse version: ' + Langfuse::VERSION
client = Langfuse.new(public_key: 'test', secret_key: 'test')
puts 'Client created successfully'
"
```

### 3.2 本地测试安装

```bash
# 卸载开发版本
gem uninstall langfuse-ruby --force

# 从 RubyGems 安装
gem install langfuse-ruby

# 运行示例测试
ruby examples/basic_tracing.rb
```

## 🔧 配置 RubyGems

### 4.1 设置账户

```bash
# 注册 RubyGems 账户 (如果还没有)
# 访问 https://rubygems.org/sign_up

# 登录 RubyGems
gem signin

# 或手动设置 API 密钥
echo "---" > ~/.gem/credentials
echo ":rubygems_api_key: YOUR_API_KEY" >> ~/.gem/credentials
chmod 0600 ~/.gem/credentials
```

### 4.2 自动化发布（可选）

使用 GitHub Actions 自动化发布：

1. 在 GitHub 仓库设置中添加 `RUBYGEMS_API_KEY` 密钥
2. 创建 `.github/workflows/release.yml`

## 📝 发布检查清单

### 发布前必须完成

- [ ] 所有测试通过 (`make test`)
- [ ] 代码风格检查通过 (`make lint`)
- [ ] 更新版本号 (`lib/langfuse/version.rb`)
- [ ] 更新变更日志 (`CHANGELOG.md`)
- [ ] 更新 gemspec 中的个人信息
- [ ] 创建 Git 标签
- [ ] 推送到 GitHub

### 发布后验证

- [ ] 在 RubyGems 上验证 gem 可见
- [ ] 测试从 RubyGems 安装
- [ ] 验证基本功能正常
- [ ] 更新文档（如有必要）

## 🔄 版本更新流程

### 补丁版本 (0.1.1 → 0.1.2)

```bash
# 1. 修复问题
# 2. 更新版本号
# 3. 更新 CHANGELOG.md
# 4. 运行测试
# 5. 发布
```

### 次要版本 (0.1.1 → 0.2.0)

```bash
# 1. 添加新功能
# 2. 更新版本号
# 3. 更新 CHANGELOG.md
# 4. 更新 README.md（如有必要）
# 5. 运行完整测试
# 6. 发布
```

### 主要版本 (0.1.1 → 1.0.0)

```bash
# 1. 重大变更
# 2. 更新版本号
# 3. 更新 CHANGELOG.md（包含迁移指南）
# 4. 更新所有文档
# 5. 运行完整测试
# 6. 发布公告
```

## 🆘 常见问题

### Q: 发布失败，提示版本已存在

```bash
# 检查现有版本
gem search langfuse-ruby

# 更新版本号并重新发布
# 编辑 lib/langfuse/version.rb
git commit -am "Bump version to 0.1.2"
git tag v0.1.2
make release
```

### Q: 认证失败

```bash
# 重新登录
gem signin

# 或检查 API 密钥
cat ~/.gem/credentials
```

### Q: 如何撤回版本

```bash
# 紧急撤回（谨慎使用）
gem yank langfuse-ruby -v 0.1.1

# 发布修复版本
# 修复问题后发布新版本
```

## 📈 推广和维护

### 发布后推广

- 在 Ruby Weekly 等社区分享
- 写博客文章介绍新功能
- 在相关项目中添加集成示例
- 联系 Langfuse 官方添加到文档

### 持续维护

- 定期更新依赖项
- 监控 GitHub Issues
- 修复用户报告的问题
- 保持与 Langfuse API 的兼容性

---

更多详细信息请参考 [RubyGems 发布指南](https://guides.rubygems.org/publishing/) 和项目根目录的 [Makefile](../Makefile)。