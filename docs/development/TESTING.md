# Langfuse Ruby SDK 测试指南

本文档介绍如何运行和编写 Langfuse Ruby SDK 的测试。

## 🧪 测试套件概览

### 测试结构

```
spec/
├── spec_helper.rb              # 测试配置和辅助工具
├── langfuse/                   # 主要测试文件
│   ├── client_spec.rb         # 客户端功能测试
│   ├── trace_spec.rb          # Trace 功能测试
│   ├── span_spec.rb           # Span 功能测试
│   ├── generation_spec.rb     # Generation 功能测试
│   ├── event_spec.rb          # Event 功能测试
│   ├── prompt_spec.rb         # Prompt 模板测试
│   ├── evaluation_spec.rb     # 评估器测试
│   ├── utils_spec.rb          # 工具类测试
│   └── errors_spec.rb         # 错误处理测试
└── support/
    └── offline_mode_helper.rb # 离线测试辅助工具
```

## 🚀 运行测试

### 快速开始

```bash
# 运行所有测试
make test

# 或使用 RSpec 直接运行
bundle exec rspec

# 快速测试（不包含覆盖率）
make quick-test
```

### 运行特定测试

```bash
# 测试特定文件
bundle exec rspec spec/langfuse/client_spec.rb

# 测试特定功能
bundle exec rspec spec/langfuse/client_spec.rb:15

# 测试特定标签
bundle exec rspec --tag ~slow  # 排除慢速测试
```

### 测试覆盖率

```bash
# 生成覆盖率报告
make test-coverage

# 查看详细覆盖率
open coverage/index.html
```

## 🛠️ 测试配置

### 环境变量

测试可以通过环境变量配置：

```bash
# 启用调试模式
LANGFUSE_DEBUG=true bundle exec rspec

# 设置测试主机
LANGFUSE_HOST=http://localhost:3000 bundle exec rspec
```

### 测试配置文件

`spec/spec_helper.rb` 包含：

- 测试环境设置
- VCR 配置（HTTP 请求模拟）
- 测试清理机制
- 共享辅助方法

## 📝 离线测试

### 离线模式辅助工具

`spec/support/offline_mode_helper.rb` 提供了无需 API 密钥的测试工具：

```ruby
# 在测试中使用
require 'support/offline_mode_helper'

RSpec.describe "Offline functionality" do
  include OfflineModeHelper

  let(:client) { create_offline_client }

  it "works without network" do
    trace = create_complex_trace(client)
    expect(trace.id).to be_present
  end
end
```

### 主要离线测试功能

- **客户端初始化测试** - 验证配置和认证
- **事件创建测试** - 验证 Trace、Span、Generation 创建
- **数据序列化测试** - 验证事件数据格式
- **错误处理测试** - 验证异常处理逻辑
- **工具函数测试** - 验证辅助函数功能

## 🔧 编写新测试

### 基本测试结构

```ruby
RSpec.describe Langfuse::Client do
  let(:client) { create_offline_client }

  after { cleanup_client(client) }

  describe "#trace" do
    it "creates a trace with valid parameters" do
      trace = client.trace(name: "test-trace")

      expect(trace).to be_a(Langfuse::Trace)
      expect(trace.name).to eq("test-trace")
      expect(trace.id).to be_present
    end
  end
end
```

### 测试最佳实践

1. **使用离线模式** - 避免依赖网络连接
2. **清理资源** - 使用 `after` 钩子清理客户端
3. **验证状态** - 检查对象属性和队列状态
4. **测试边界情况** - 包含错误和异常情况
5. **使用描述性名称** - 让测试意图清晰

### 异步测试

```ruby
it "handles background flushing" do
  client = create_offline_client(auto_flush: false)

  # 添加事件
  trace = client.trace(name: "async-test")

  # 验证事件在队列中
  expect(queue_size(client)).to eq(1)

  # 手动刷新
  client.flush

  # 验证队列已清空
  expect(queue_size(client)).to eq(0)
end
```

## 🐛 调试测试

### 启用详细输出

```bash
# 详细模式
bundle exec rspec --format documentation

# 调试模式
bundle exec rspec --format documentation --backtrace
```

### 测试特定功能

```bash
# 只运行失败的测试
bundle exec rspec --only-failures

# 运行特定行数的测试
bundle exec rspec spec/langfuse/client_spec.rb:25:30
```

### 调试技巧

```ruby
# 在测试中添加调试输出
it "debug example" do
  client = create_offline_client(debug: true)

  # 检查队列状态
  puts "Queue size: #{queue_size(client)}"
  puts "Queued events: #{get_queued_events(client)}"

  # 验证行为
  expect(client).to be_truthy
end
```

## 📊 测试覆盖范围

### 当前测试覆盖

- ✅ **客户端功能** - 初始化、配置、事件管理
- ✅ **追踪系统** - Trace、Span、Generation 创建和管理
- ✅ **事件系统** - Event 创建和处理
- ✅ **评分系统** - Score 创建和管理
- ✅ **提示管理** - Prompt 模板和编译
- ✅ **评估器** - 内置评估器功能
- ✅ **工具函数** - ID 生成、时间戳、数据转换
- ✅ **错误处理** - 异常类型和处理逻辑
- ✅ **异步处理** - 后台线程和事件队列

### 测试统计

```bash
# 查看测试统计
bundle exec rspec --format progress

# 预期输出：
# 23 examples, 0 failures
# Coverage: 95.2%
```

## 🔗 集成测试

### 网络模拟测试

使用 VCR 模拟真实 API 调用：

```ruby
require 'vcr'

VCR.use_cassette("client_auth") do
  client = Langfuse.new(
    public_key: "test-key",
    secret_key: "test-secret"
  )

  # 测试实际 API 交互
  expect(client).to be_truthy
end
```

### 性能测试

```ruby
it "handles large numbers of events efficiently" do
  client = create_offline_client(auto_flush: false)
  start_time = Time.now

  1000.times do |i|
    client.trace(name: "trace-#{i}")
  end

  elapsed_time = Time.now - start_time

  # 验证性能
  expect(elapsed_time).to be < 1.0  # 应在1秒内完成
  expect(queue_size(client)).to eq(1000)
end
```

## 🚨 常见问题

### 测试失败排查

1. **清理不完整** - 确保使用 `cleanup_client`
2. **时序问题** - 使用 `sleep` 或等待机制
3. **环境变量** - 检查测试环境设置
4. **依赖冲突** - 运行 `bundle update`

### 内存泄漏检查

```ruby
it "does not leak memory" do
  # 获取初始内存使用
  GC.start
  initial_objects = ObjectSpace.count_objects

  # 执行测试操作
  100.times { client.trace(name: "test") }
  cleanup_client(client)

  # 检查内存使用
  GC.start
  final_objects = ObjectSpace.count_objects

  # 验证没有明显的内存泄漏
  expect(final_objects[:TOTAL] - initial_objects[:TOTAL]).to be < 1000
end
```

## 📝 贡献指南

### 添加新测试

1. 在相应的 `spec/langfuse/*_spec.rb` 文件中添加测试
2. 使用离线模式辅助工具
3. 包含正面和负面测试用例
4. 确保测试后清理资源

### 运行完整测试套件

在提交 PR 前，确保：

```bash
# 运行所有检查
make check

# 验证没有回归
bundle exec rspec
```

---

更多测试相关信息请参考 [RSpec 文档](https://rspec.info/) 和项目根目录的 [Makefile](../Makefile)。