# 类型验证错误故障排除指南

## 问题描述

当您遇到以下错误时：

```json
{
  "id": "xxx",
  "status": 400,
  "message": "Invalid request data",
  "error": [
    {
      "code": "invalid_union",
      "errors": [],
      "note": "No matching discriminator", 
      "path": ["type"],
      "message": "Invalid input"
    }
  ]
}
```

这表示 Langfuse 服务器端的 API 验证发现事件的 `type` 字段不符合预期的格式。

## 根本原因

1. **事件类型无效**: 发送的事件类型不在服务器端支持的列表中
2. **事件数据结构错误**: 事件的数据结构不符合对应类型的要求
3. **数据序列化问题**: 事件数据在序列化过程中出现问题

## 常见修复案例

### 1. 事件类型无效

```ruby
client.trace(name: "my-trace", user_id: "user-123", input: { query: "Hello" })
```

## 解决方案

### 1. 启用调试模式

```ruby
client = Langfuse.new(
  public_key: "your-key",
  secret_key: "your-secret",
  debug: true  # 启用调试模式
)
```

调试模式会显示：
- 发送的事件类型
- 事件数据结构
- 详细的错误信息

### 2. 检查支持的事件类型

当前支持的事件类型：
- `trace-create`
- `generation-create`
- `generation-update`
- `span-create`
- `span-update`
- `event-create`
- `score-create`

### 3. 验证事件数据

确保事件数据包含必要的字段：

#### Trace 事件
```ruby
{
  id: "uuid",
  name: "trace-name",
  user_id: "user-id",
  input: { ... },
  metadata: { ... },
  tags: [...],
  timestamp: "2025-01-01T00:00:00.000Z"
}
```

#### Generation 事件
```ruby
{
  id: "uuid",
  trace_id: "trace-uuid",
  name: "generation-name",
  model: "gpt-3.5-turbo",
  input: [...],
  output: { ... },
  usage: { ... },
  metadata: { ... }
}
```

#### Span 事件
```ruby
{
  id: "uuid",
  trace_id: "trace-uuid",
  name: "span-name",
  start_time: "2025-01-01T00:00:00.000Z",
  end_time: "2025-01-01T00:00:01.000Z",
  input: { ... },
  output: { ... },
  metadata: { ... }
}
```

#### Event 事件
```ruby

```ruby

```

#### Score 事件
```ruby

```

### 4. 检查网络和认证

确保：
- API 密钥正确
- 网络连接正常
- 服务器端点可访问

### 5. 使用错误处理

```ruby
begin
  client.flush
rescue Langfuse::ValidationError => e
  if e.message.include?('Event type validation failed')
    puts "类型验证错误: #{e.message}"
    # 检查事件数据格式
  else
    puts "其他验证错误: #{e.message}"
  end
rescue Langfuse::APIError => e
  puts "API 错误: #{e.message}"
end
```

## 预防措施

1. **使用官方 SDK 方法**: 避免直接构造事件数据
2. **数据验证**: 在发送前验证数据完整性
3. **错误监控**: 实施适当的错误处理和监控
4. **测试环境**: 在测试环境中验证集成
5. **保持更新**: 定期更新 SDK 到最新版本

## 示例代码

```ruby
# 正确的使用方式
client = Langfuse.new(
  public_key: "pk-lf-xxx",
  secret_key: "sk-lf-xxx",
  debug: true
)

# 创建 trace
trace = client.trace(
  name: "my-trace",
  user_id: "user-123",
  input: { query: "Hello" }
)

# 创建 generation
generation = trace.generation(
  name: "my-generation",
  model: "gpt-3.5-turbo",
  input: [{ role: "user", content: "Hello" }],
  output: { content: "Hi there!" }
)

# 安全地刷新事件
begin
  client.flush
  puts "事件发送成功"
rescue => e
  puts "发送失败: #{e.message}"
end
```

## 联系支持

如果问题持续存在，请提供：
1. 完整的错误消息
2. 调试模式的输出
3. 相关的代码片段
4. SDK 版本信息

## 更新日志

- v0.1.1: 改进了错误消息的可读性
- v0.1.0: 初始版本 
