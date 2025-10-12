# API 验证错误故障排除

当遇到 Langfuse API 验证错误时，本指南帮助您诊断和解决问题。

## 🚨 常见错误类型

### 1. 事件类型验证错误

```json
{
  "status": 400,
  "message": "Invalid request data",
  "error": [
    {
      "code": "invalid_union",
      "message": "Invalid input",
      "path": ["type"],
      "note": "No matching discriminator"
    }
  ]
}
```

**原因**: 发送的事件类型不在服务器支持的列表中。

### 2. 数据结构验证错误

```json
{
  "status": 400,
  "message": "Missing required field",
  "error": [
    {
      "code": "missing_field",
      "path": ["trace_id"],
      "message": "Field is required"
    }
  ]
}
```

**原因**: 事件缺少必需的字段。

### 3. 认证错误

```json
{
  "status": 401,
  "message": "Authentication failed",
  "error": "Invalid API credentials"
}
```

**原因**: API 密钥无效或缺失。

## 🛠️ 诊断步骤

### 1. 启用调试模式

```ruby
client = Langfuse.new(
  public_key: "your-public-key",
  secret_key: "your-secret-key",
  debug: true  # 启用调试输出
)
```

调试模式会显示：
- 发送的事件数据
- HTTP 请求详情
- 服务器响应

### 2. 验证事件数据结构

确保事件包含正确的字段：

#### Trace 事件
```ruby
{
  id: "uuid-v4",
  name: "trace-name",
  user_id: "user-id",
  session_id: "session-id",      # 可选
  input: { ... },               # 可选
  output: { ... },              # 可选
  metadata: { ... },            # 可选
  tags: ["tag1", "tag2"],       # 可选
  timestamp: "2025-01-01T00:00:00.000Z"
}
```

#### Generation 事件
```ruby
{
  id: "uuid-v4",
  trace_id: "trace-uuid",
  name: "generation-name",
  model: "gpt-3.5-turbo",
  input: [...],                 # 消息数组
  output: { ... },              # 响应对象
  usage: {                      # 可选
    prompt_tokens: 10,
    completion_tokens: 15,
    total_tokens: 25
  },
  metadata: { ... },            # 可选
  model_parameters: { ... }     # 可选
}
```

#### Span 事件
```ruby
{
  id: "uuid-v4",
  trace_id: "trace-uuid",
  name: "span-name",
  start_time: "2025-01-01T00:00:00.000Z",
  end_time: "2025-01-01T00:00:01.000Z",  # 可选
  input: { ... },               # 可选
  output: { ... },              # 可选
  metadata: { ... }             # 可选
}
```

### 3. 检查支持的事件类型

当前支持的事件类型：
- `trace-create`
- `trace-update`
- `generation-create`
- `generation-update`
- `span-create`
- `span-update`
- `event-create`
- `score-create`

## 🔧 解决方案

### 方案 1: 使用正确的 SDK 方法

避免手动构造事件数据，使用 SDK 提供的方法：

```ruby
# ❌ 错误方式 - 手动构造事件
# client.post("/ingestion", { type: "invalid-event", ... })

# ✅ 正确方式 - 使用 SDK 方法
trace = client.trace(
  name: "my-trace",
  user_id: "user-123",
  input: { query: "Hello" }
)

generation = trace.generation(
  name: "my-generation",
  model: "gpt-3.5-turbo",
  input: [{ role: "user", content: "Hello" }],
  output: { content: "Hi there!" }
)
```

### 方案 2: 验证必需字段

```ruby
def validate_trace_data(data)
  required_fields = [:id, :name]
  missing_fields = required_fields - data.keys

  unless missing_fields.empty?
    raise ArgumentError, "Missing required fields: #{missing_fields.join(', ')}"
  end

  # 验证 ID 格式
  unless data[:id] =~ /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    raise ArgumentError, "Invalid ID format: #{data[:id]}"
  end
end
```

### 方案 3: 添加错误处理

```ruby
def safe_flush_events(client)
  begin
    client.flush
    puts "✅ Events sent successfully"
  rescue Langfuse::ValidationError => e
    puts "❌ Validation error: #{e.message}"
    # 检查事件数据格式
    debug_queued_events(client)
  rescue Langfuse::AuthenticationError => e
    puts "❌ Authentication error: #{e.message}"
    # 检查 API 密钥
  rescue Langfuse::APIError => e
    puts "❌ API error: #{e.message}"
    # 检查网络连接和服务器状态
  rescue => e
    puts "❌ Unexpected error: #{e.message}"
    puts e.backtrace.first(5)
  end
end

def debug_queued_events(client)
  events = client.instance_variable_get(:@event_queue)
  events.each_with_index do |event, index|
    puts "Event #{index + 1}:"
    puts "  Type: #{event[:type]}"
    puts "  Data: #{event.to_json}"
    puts "---"
  end
end
```

### 方案 4: 批量验证事件

```ruby
def validate_events_before_flush(client)
  events = client.instance_variable_get(:@event_queue)
  valid_events = []
  invalid_events = []

  events.each do |event|
    if event_valid?(event)
      valid_events << event
    else
      invalid_events << event
    end
  end

  unless invalid_events.empty?
    puts "⚠️ Found #{invalid_events.size} invalid events:"
    invalid_events.each { |e| puts "  #{e[:type]}: #{e[:id]}" }
  end

  # 只发送有效事件
  client.instance_variable_set(:@event_queue, valid_events)
end

def event_valid?(event)
  case event[:type]
  when 'trace-create', 'trace-update'
    event[:id] && event[:name]
  when 'generation-create', 'generation-update'
    event[:id] && event[:trace_id] && event[:model]
  when 'span-create', 'span-update'
    event[:id] && event[:trace_id] && event[:name]
  else
    false
  end
end
```

## 🧪 测试和验证

### 本地验证

```ruby
# 创建测试客户端
client = Langfuse.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  debug: true,
  auto_flush: false  # 禁用自动刷新以便检查
)

# 创建测试事件
trace = client.trace(
  name: "test-trace",
  user_id: "test-user",
  input: { message: "Hello, world!" }
)

# 手动验证事件
events = client.instance_variable_get(:@event_queue)
puts "Queued events: #{events.size}"
events.each { |e| puts e.to_json }

# 尝试发送
safe_flush_events(client)
```

### 使用测试环境

```ruby
# 使用测试主机
client = Langfuse.new(
  public_key: "test-key",
  secret_key: "test-secret",
  host: "http://localhost:3000",  # 本地测试实例
  debug: true
)
```

## 📋 预防措施

### 1. 数据验证

```ruby
class EventValidator
  def self.validate_trace(data)
    validate_required_fields(data, [:id, :name])
    validate_uuid_format(data[:id])
    validate_timestamp(data[:timestamp]) if data[:timestamp]
  end

  def self.validate_generation(data)
    validate_required_fields(data, [:id, :trace_id, :model])
    validate_uuid_format(data[:id])
    validate_uuid_format(data[:trace_id])
  end

  private

  def self.validate_required_fields(data, fields)
    missing = fields - data.keys
    raise ArgumentError, "Missing required fields: #{missing.join(', ')}" unless missing.empty?
  end

  def self.validate_uuid_format(id)
    unless id =~ /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
      raise ArgumentError, "Invalid UUID format: #{id}"
    end
  end

  def self.validate_timestamp(timestamp)
    Time.parse(timestamp)
  rescue ArgumentError
    raise ArgumentError, "Invalid timestamp format: #{timestamp}"
  end
end
```

### 2. 环境检查

```ruby
def validate_environment
  required_env_vars = %w[LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY]
  missing_vars = required_env_vars.select { |var| ENV[var].nil? || ENV[var].empty? }

  unless missing_vars.empty?
    raise "Missing required environment variables: #{missing_vars.join(', ')}"
  end

  if ENV['LANGFUSE_HOST'] && !URI.parse(ENV['LANGFUSE_HOST']).is_a?(URI::HTTP)
    raise "Invalid LANGFUSE_HOST format: #{ENV['LANGFUSE_HOST']}"
  end
end
```

### 3. 健康检查

```ruby
def check_client_health(client)
  begin
    # 尝试发送一个小的测试事件
    test_trace = client.trace(name: "health-check")
    test_event_count = client.instance_variable_get(:@event_queue).size

    client.flush

    # 验证事件已发送
    final_event_count = client.instance_variable_get(:@event_queue).size
    final_event_count < test_event_count
  rescue => e
    puts "Health check failed: #{e.message}"
    false
  end
end
```

## 📞 获取帮助

如果问题持续存在，请提供以下信息：

1. **完整错误消息** - 包括状态码和错误详情
2. **调试输出** - 启用 debug: true 的输出
3. **SDK 版本** - `Langfuse::VERSION`
4. **重现步骤** - 最小化的问题示例
5. **环境信息** - Ruby 版本、操作系统等

### 联系方式

- GitHub Issues: [langfuse-ruby/issues](https://github.com/ai-firstly/langfuse-ruby/issues)
- Langfuse 官方文档: [docs.langfuse.com](https://docs.langfuse.com)
- RubyGems: [rubygems.org/gems/langfuse-ruby](https://rubygems.org/gems/langfuse-ruby)

---

更多故障排除信息请参考项目 [README](../../README.md) 和 [API 文档](https://api.reference.langfuse.com)。