#!/usr/bin/env ruby

require_relative '../lib/langfuse'

puts '🚀 Langfuse Ruby SDK 连接配置演示'
puts '=' * 50

# 显示默认配置
puts "\n📋 默认配置信息:"
puts "   默认主机: #{Langfuse.configuration.host}"
puts "   默认超时: #{Langfuse.configuration.timeout}秒"
puts "   默认重试: #{Langfuse.configuration.retries}次"

# 方法 1: 使用测试密钥创建客户端（仅用于演示）
puts "\n📝 方法 1: 直接参数配置"
puts '代码示例：'
puts 'client = Langfuse.new('
puts "  public_key: 'pk-lf-your-public-key',"
puts "  secret_key: 'sk-lf-your-secret-key',"
puts "  host: 'https://us.cloud.langfuse.com'"
puts ')'

# 使用测试密钥创建客户端
test_client = Langfuse.new(
  public_key: 'test-public-key',
  secret_key: 'test-secret-key',
  host: 'https://us.cloud.langfuse.com'
)

puts '✅ 客户端配置成功'
puts "   主机: #{test_client.host}"
puts "   超时: #{test_client.timeout}秒"
puts "   重试: #{test_client.retries}次"

# 方法 2: 全局配置
puts "\n📝 方法 2: 全局配置"
puts '代码示例：'
puts 'Langfuse.configure do |config|'
puts "  config.public_key = 'pk-lf-your-public-key'"
puts "  config.secret_key = 'sk-lf-your-secret-key'"
puts "  config.host = 'https://us.cloud.langfuse.com'"
puts '  config.debug = true'
puts 'end'

Langfuse.configure do |config|
  config.public_key = 'test-public-key'
  config.secret_key = 'test-secret-key'
  config.host = 'https://us.cloud.langfuse.com'
  config.debug = true
  config.timeout = 60
  config.retries = 5
end

global_client = Langfuse.new
puts '✅ 全局配置成功'
puts "   主机: #{global_client.host}"
puts "   调试模式: #{global_client.debug}"
puts "   超时: #{global_client.timeout}秒"
puts "   重试: #{global_client.retries}次"

# 方法 3: 环境变量配置
puts "\n📝 方法 3: 环境变量配置"
puts '设置环境变量：'
puts "export LANGFUSE_PUBLIC_KEY='pk-lf-your-public-key'"
puts "export LANGFUSE_SECRET_KEY='sk-lf-your-secret-key'"
puts "export LANGFUSE_HOST='https://us.cloud.langfuse.com'"
puts ''
puts '然后使用：'
puts 'client = Langfuse.new'

if ENV['LANGFUSE_PUBLIC_KEY'] && ENV['LANGFUSE_SECRET_KEY']
  env_client = Langfuse.new
  puts '✅ 环境变量配置成功'
  puts "   主机: #{env_client.host}"
else
  puts '⚠️  环境变量未设置，跳过此示例'
end

# 连接配置详情
puts "\n🔧 连接配置详情:"
puts '根据 Langfuse 官方文档:'
puts '1. 认证方式: HTTP Basic Auth'
puts '2. 用户名: Langfuse Public Key (pk-lf-...)'
puts '3. 密码: Langfuse Secret Key (sk-lf-...)'
puts '4. 默认服务器: https://us.cloud.langfuse.com'
puts '5. 内容类型: application/json'
puts "6. User-Agent: langfuse-ruby/#{Langfuse::VERSION}"

# 创建测试 trace（不发送到服务器）
puts "\n🧪 创建测试 Trace（离线）:"
begin
  trace = test_client.trace(
    name: 'connection-test',
    user_id: 'demo-user',
    input: { message: '测试连接配置' },
    metadata: { demo: true }
  )

  puts '✅ Trace 创建成功'
  puts "   ID: #{trace.id}"
  puts "   名称: #{trace.name}"
  puts "   用户ID: #{trace.user_id}"

  # 添加 generation
  generation = trace.generation(
    name: 'demo-generation',
    model: 'gpt-3.5-turbo',
    input: [{ role: 'user', content: 'Hello!' }],
    output: { content: '你好！' },
    usage: { prompt_tokens: 5, completion_tokens: 3, total_tokens: 8 }
  )

  puts '✅ Generation 创建成功'
  puts "   ID: #{generation.id}"
  puts "   模型: #{generation.model}"
rescue StandardError => e
  puts "❌ 测试失败: #{e.message}"
end

puts "\n📚 使用提示:"
puts "1. 替换示例中的 'test-public-key' 和 'test-secret-key' 为您的真实 API 密钥"
puts '2. 确保网络连接正常'
puts '3. 启用 debug 模式可以查看详细的请求日志'
puts '4. 调用 client.flush 来发送事件到服务器'
puts '5. 使用 client.shutdown 来优雅地关闭客户端'

puts "\n🎉 连接配置演示完成！"
