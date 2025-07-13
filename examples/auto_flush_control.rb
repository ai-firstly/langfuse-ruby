#!/usr/bin/env ruby

require_relative '../lib/langfuse'

puts '🚀 Langfuse Ruby SDK 自动刷新控制演示'
puts '=' * 50

# 示例 1: 启用自动刷新（默认行为）
puts "\n📝 示例 1: 启用自动刷新（默认行为）"
puts '代码示例：'
puts 'client = Langfuse.new('
puts "  public_key: 'pk-lf-your-public-key',"
puts "  secret_key: 'sk-lf-your-secret-key',"
puts '  auto_flush: true  # 默认为 true，可以省略'
puts ')'

client_auto = Langfuse.new(
  public_key: 'test-public-key',
  secret_key: 'test-secret-key',
  auto_flush: true,
  flush_interval: 2 # 2秒刷新一次用于演示
)

puts '✅ 自动刷新客户端创建成功'
puts "   自动刷新: #{client_auto.auto_flush}"
puts "   刷新间隔: #{client_auto.flush_interval}秒"

# 创建一些事件
trace_auto = client_auto.trace(
  name: 'auto-flush-demo',
  input: { message: '这是自动刷新演示' },
  metadata: { demo: true }
)

puts '✅ 创建了 trace，将在后台自动刷新'

# 示例 2: 禁用自动刷新
puts "\n📝 示例 2: 禁用自动刷新"
puts '代码示例：'
puts 'client = Langfuse.new('
puts "  public_key: 'pk-lf-your-public-key',"
puts "  secret_key: 'sk-lf-your-secret-key',"
puts '  auto_flush: false  # 禁用自动刷新'
puts ')'

client_manual = Langfuse.new(
  public_key: 'test-public-key',
  secret_key: 'test-secret-key',
  auto_flush: false
)

puts '✅ 手动刷新客户端创建成功'
puts "   自动刷新: #{client_manual.auto_flush}"
puts "   刷新间隔: #{client_manual.flush_interval}秒（不会自动刷新）"

# 创建一些事件
trace_manual = client_manual.trace(
  name: 'manual-flush-demo',
  input: { message: '这是手动刷新演示' },
  metadata: { demo: true }
)

generation_manual = trace_manual.generation(
  name: 'manual-generation',
  model: 'gpt-3.5-turbo',
  input: [{ role: 'user', content: 'Hello!' }],
  output: { content: '你好！' },
  usage: { prompt_tokens: 5, completion_tokens: 3, total_tokens: 8 }
)

puts '✅ 创建了 trace 和 generation，需要手动刷新'
puts "   事件队列长度: #{client_manual.instance_variable_get(:@event_queue).length}"

# 手动刷新（离线模式，不实际发送）
puts "\n🔄 手动刷新事件（离线模式）..."
puts '   注意：在实际应用中，这里会发送事件到 Langfuse 服务器'
puts '   当前为演示模式，不会实际发送请求'
# client_manual.flush  # 注释掉以避免网络请求
puts "   事件队列长度: #{client_manual.instance_variable_get(:@event_queue).length}"

# 示例 3: 通过全局配置控制
puts "\n📝 示例 3: 通过全局配置控制"
puts '代码示例：'
puts 'Langfuse.configure do |config|'
puts "  config.public_key = 'pk-lf-your-public-key'"
puts "  config.secret_key = 'sk-lf-your-secret-key'"
puts '  config.auto_flush = false  # 全局禁用自动刷新'
puts '  config.flush_interval = 10'
puts 'end'

Langfuse.configure do |config|
  config.public_key = 'test-public-key'
  config.secret_key = 'test-secret-key'
  config.auto_flush = false
  config.flush_interval = 10
end

client_global = Langfuse.new
puts '✅ 全局配置客户端创建成功'
puts "   自动刷新: #{client_global.auto_flush}"
puts "   刷新间隔: #{client_global.flush_interval}秒"

# 示例 4: 通过环境变量控制
puts "\n📝 示例 4: 通过环境变量控制"
puts '设置环境变量：'
puts "export LANGFUSE_PUBLIC_KEY='pk-lf-your-public-key'"
puts "export LANGFUSE_SECRET_KEY='sk-lf-your-secret-key'"
puts 'export LANGFUSE_AUTO_FLUSH=false'
puts 'export LANGFUSE_FLUSH_INTERVAL=15'
puts ''
puts '然后使用：'
puts 'client = Langfuse.new'

# 模拟环境变量
ENV['LANGFUSE_AUTO_FLUSH'] = 'false'
ENV['LANGFUSE_FLUSH_INTERVAL'] = '15'

client_env = Langfuse.new(
  public_key: 'test-public-key',
  secret_key: 'test-secret-key'
)

puts '✅ 环境变量配置客户端创建成功'
puts "   自动刷新: #{client_env.auto_flush}"
puts "   刷新间隔: #{client_env.flush_interval}秒"

# 清理环境变量
ENV.delete('LANGFUSE_AUTO_FLUSH')
ENV.delete('LANGFUSE_FLUSH_INTERVAL')

# 示例 5: 混合使用场景
puts "\n📝 示例 5: 混合使用场景"
puts '在某些情况下，您可能希望：'
puts '1. 大部分时间使用自动刷新'
puts '2. 在批量操作时临时禁用自动刷新'
puts '3. 在操作完成后手动刷新'

# 批量操作示例
puts "\n🔄 批量操作演示..."
batch_client = Langfuse.new(
  public_key: 'test-public-key',
  secret_key: 'test-secret-key',
  auto_flush: false # 禁用自动刷新以提高批量操作性能
)

# 批量创建多个 traces
traces = []
10.times do |i|
  trace = batch_client.trace(
    name: "batch-trace-#{i}",
    input: { batch_id: i },
    metadata: { batch_operation: true }
  )
  traces << trace
end

puts "✅ 批量创建了 #{traces.length} 个 traces"
puts "   事件队列长度: #{batch_client.instance_variable_get(:@event_queue).length}"

# 批量操作完成后手动刷新（离线模式）
puts "\n🔄 批量操作完成，执行手动刷新（离线模式）..."
puts '   注意：在实际应用中，这里会发送所有事件到 Langfuse 服务器'
# batch_client.flush  # 注释掉以避免网络请求
puts "   事件队列长度: #{batch_client.instance_variable_get(:@event_queue).length}（未发送）"

# 使用建议
puts "\n💡 使用建议:"
puts '1. 默认情况下保持 auto_flush=true，适合大多数应用场景'
puts '2. 在批量操作或高频操作时，考虑设置 auto_flush=false'
puts '3. 禁用自动刷新时，记得在适当的时机调用 client.flush'
puts '4. 应用关闭前，务必调用 client.shutdown 确保所有事件都被发送'
puts '5. 可以通过环境变量在不同环境中控制刷新行为'

# 性能对比
puts "\n⚡ 性能对比:"
puts '自动刷新模式：'
puts '  - 优点：无需手动管理，事件及时发送'
puts '  - 缺点：后台线程消耗资源，可能影响高频操作性能'
puts ''
puts '手动刷新模式：'
puts '  - 优点：更好的性能控制，适合批量操作'
puts '  - 缺点：需要手动管理刷新时机，容易遗漏'

# 等待一下让自动刷新客户端工作
puts "\n⏳ 等待自动刷新客户端工作..."
sleep(3)

# 关闭所有客户端（离线模式）
puts "\n🔒 关闭所有客户端（离线模式）..."
puts '   注意：在实际应用中，shutdown 会确保所有事件都被发送'
# 在演示模式下，我们只终止后台线程而不发送请求
client_auto.instance_variable_get(:@flush_thread)&.kill
client_manual.instance_variable_get(:@flush_thread)&.kill
client_global.instance_variable_get(:@flush_thread)&.kill
client_env.instance_variable_get(:@flush_thread)&.kill
batch_client.instance_variable_get(:@flush_thread)&.kill

puts "\n🎉 自动刷新控制演示完成！"
puts ''
puts '📚 总结：'
puts '现在您可以在应用层面灵活控制 Langfuse 的自动刷新行为：'
puts '- 通过构造函数参数 auto_flush 控制'
puts '- 通过全局配置 Langfuse.configure 控制'
puts '- 通过环境变量 LANGFUSE_AUTO_FLUSH 控制'
puts '- 根据不同场景选择合适的刷新策略'
