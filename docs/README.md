# Langfuse Ruby SDK 文档

欢迎使用 Langfuse Ruby SDK 文档！这里包含了使用、开发和维护 SDK 的完整指南。

## 📚 文档目录

### 🚀 快速开始
- [主要 README](../README.md) - 项目介绍、安装指南和基本用法
- [示例代码](../examples/) - 实际使用示例和最佳实践

### 🛠️ 开发指南
- [测试指南](development/TESTING.md) - 如何运行和编写测试
- [发布指南](development/RELEASE_GUIDE.md) - 详细的发布流程和配置
- [发布检查清单](development/RELEASE_CHECKLIST.md) - 发布前的检查项目

### 🔧 故障排除
- [API 验证错误](troubleshooting/API_VALIDATION.md) - 常见 API 错误的诊断和解决

### 📖 参考资料
- [API 参考](https://api.reference.langfuse.com) - Langfuse API 官方文档
- [RubyGems](https://rubygems.org/gems/langfuse-ruby) - Gem 页面和版本历史
- [GitHub 仓库](https://github.com/ai-firstly/langfuse-ruby) - 源代码和问题跟踪

### 📦 项目结构
```
langfuse-ruby/
├── lib/langfuse/          # 核心代码
├── spec/                  # 测试文件
├── examples/              # 使用示例
├── docs/                  # 文档（当前目录）
├── Makefile              # 开发任务快捷命令
└── CHANGELOG.md          # 版本变更记录
```

## 🚀 快速导航

### 用户常见需求
1. **安装 SDK** - 查看 [主 README](../README.md#installation)
2. **基本使用** - 查看 [主 README](../README.md#quick-start)
3. **示例代码** - 浏览 [examples/](../examples/) 目录
4. **配置选项** - 查看 [主 README](../README.md#configuration-options)

### 开发者常见需求
1. **运行测试** - 查看 [测试指南](development/TESTING.md#-运行测试)
2. **发布新版本** - 查看 [发布指南](development/RELEASE_GUIDE.md)
3. **代码质量检查** - 运行 `make lint` 或 `make check`
4. **贡献代码** - 查看 [贡献指南](../CONTRIBUTING.md)

### 故障排除
1. **API 验证错误** - 查看 [API 验证指南](troubleshooting/API_VALIDATION.md)
2. **认证问题** - 查看 [发布指南中的认证设置](development/RELEASE_GUIDE.md#-配置-rubygems)
3. **网络问题** - 查看 [故障排除指南](troubleshooting/API_VALIDATION.md#4-检查网络和认证)

## 🛠️ 常用开发命令

```bash
# 初始化开发环境
make setup

# 运行测试
make test

# 代码质量检查
make lint

# 构建 gem
make build

# 发布 gem
make release

# 查看所有可用命令
make help
```

## 📖 文档使用指南

### 文档优先级
1. **必须阅读** - [主 README](../README.md)（所有用户）
2. **开发者必读** - [测试指南](development/TESTING.md) 和 [发布指南](development/RELEASE_GUIDE.md)
3. **按需阅读** - [故障排除指南](troubleshooting/API_VALIDATION.md) 和 [示例代码](../examples/)

### 搜索和导航
- 使用文档内的目录快速导航
- 常用问题有直接的解决方案链接
- 技术术语有详细的解释和示例

### 文档维护
- 文档随代码更新而更新
- 重大变更会在文档中标注
- 过时内容会移动到 [archive/](archive/) 目录

## 🔗 相关链接

### 官方资源
- [Langfuse 官方网站](https://langfuse.com)
- [Langfuse 文档](https://docs.langfuse.com)
- [API 参考](https://api.reference.langfuse.com)

### 社区和支持
- [GitHub Issues](https://github.com/ai-firstly/langfuse-ruby/issues) - 报告问题和请求功能
- [GitHub Discussions](https://github.com/ai-firstly/langfuse-ruby/discussions) - 社区讨论
- [RubyGems](https://rubygems.org/gems/langfuse-ruby) - 版本历史和下载统计

### 其他 SDK
- [Python SDK](https://github.com/langfuse/langfuse-python)
- [JavaScript/TypeScript SDK](https://github.com/langfuse/langfuse-js)
- [其他语言 SDK](https://docs.langfuse.com/open-source/sdk)

## 🤝 贡献

欢迎贡献文档改进！

### 如何贡献
1. 发现文档不完整或过时
2. 提交 Issue 或 Pull Request
3. 遵循现有的文档格式和风格

### 文档标准
- 使用清晰简洁的语言
- 提供实际的代码示例
- 包含必要的链接和引用
- 保持信息的准确性和时效性

---

## 📞 获取帮助

如果您在使用 Langfuse Ruby SDK 时遇到问题：

1. **查阅文档** - 首先查看相关文档
2. **搜索已有问题** - 查看 [GitHub Issues](https://github.com/ai-firstly/langfuse-ruby/issues)
3. **提交新问题** - 如果没有找到解决方案，创建新的 Issue
4. **联系社区** - 在讨论区寻求帮助

感谢您使用 Langfuse Ruby SDK！🚀 