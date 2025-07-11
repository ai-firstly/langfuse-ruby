#!/usr/bin/env ruby

require 'langfuse'

# Initialize the Langfuse client
client = Langfuse.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

puts "🚀 Starting prompt management example..."

# Example 1: Create and use text prompts
puts "\n📝 Example 1: Create and use text prompts"

begin
  # Create a text prompt
  text_prompt = client.create_prompt(
    name: "greeting-prompt",
    prompt: "Hello {{user_name}}! Welcome to {{service_name}}. How can I help you with {{topic}} today?",
    labels: ["greeting", "customer-service"],
    config: {
      temperature: 0.7,
      max_tokens: 100
    }
  )

  puts "Created text prompt: #{text_prompt.name} (Version: #{text_prompt.version})"

rescue Langfuse::APIError => e
  puts "Note: Prompt might already exist - #{e.message}"
end

# Get and use the prompt
begin
  prompt = client.get_prompt("greeting-prompt")

  # Compile prompt with variables
  compiled_text = prompt.compile(
    user_name: "Alice",
    service_name: "AI Assistant",
    topic: "machine learning"
  )

  puts "Compiled prompt: #{compiled_text}"

rescue Langfuse::APIError => e
  puts "Could not retrieve prompt: #{e.message}"
end

# Example 2: Create and use chat prompts
puts "\n💬 Example 2: Create and use chat prompts"

begin
  # Create a chat prompt
  chat_prompt = client.create_prompt(
    name: "ai-assistant-chat",
    prompt: [
      {
        role: "system",
        content: "You are a helpful AI assistant specialized in {{domain}}. Always be {{tone}} and provide {{detail_level}} answers."
      },
      {
        role: "user",
        content: "{{user_message}}"
      }
    ],
    labels: ["chat", "assistant", "ai"],
    config: {
      temperature: 0.8,
      max_tokens: 200
    }
  )

  puts "Created chat prompt: #{chat_prompt.name}"

rescue Langfuse::APIError => e
  puts "Note: Chat prompt might already exist - #{e.message}"
end

# Get and use the chat prompt
begin
  chat_prompt = client.get_prompt("ai-assistant-chat")

  # Compile chat prompt with variables
  compiled_messages = chat_prompt.compile(
    domain: "software development",
    tone: "friendly and professional",
    detail_level: "detailed",
    user_message: "How do I implement a REST API in Ruby?"
  )

  puts "Compiled chat messages:"
  compiled_messages.each_with_index do |message, index|
    puts "  #{index + 1}. #{message[:role]}: #{message[:content]}"
  end

rescue Langfuse::APIError => e
  puts "Could not retrieve chat prompt: #{e.message}"
end

# Example 3: Using prompt templates
puts "\n🎨 Example 3: Using prompt templates"

# Create a reusable text template
translation_template = Langfuse::PromptTemplate.from_template(
  "Translate the following {{source_language}} text to {{target_language}}:\n\n{{text}}\n\nTranslation:"
)

puts "Template variables: #{translation_template.input_variables}"

# Use the template
translated_prompt = translation_template.format(
  source_language: "English",
  target_language: "Spanish",
  text: "Hello, how are you today?"
)

puts "Translation prompt: #{translated_prompt}"

# Create a reusable chat template
coding_template = Langfuse::ChatPromptTemplate.from_messages([
  {
    role: "system",
    content: "You are an expert {{language}} developer. Provide clean, well-commented code examples."
  },
  {
    role: "user",
    content: "{{request}}"
  }
])

puts "Chat template variables: #{coding_template.input_variables}"

# Use the chat template
coding_messages = coding_template.format(
  language: "Ruby",
  request: "Show me how to create a simple HTTP server"
)

puts "Coding chat messages:"
coding_messages.each_with_index do |message, index|
  puts "  #{index + 1}. #{message[:role]}: #{message[:content]}"
end

# Example 4: Prompt versioning and caching
puts "\n🔄 Example 4: Prompt versioning and caching"

# Get specific version of a prompt
begin
  versioned_prompt = client.get_prompt("greeting-prompt", version: 1)
  puts "Retrieved prompt version: #{versioned_prompt.version}"

  # Get latest version (cached)
  latest_prompt = client.get_prompt("greeting-prompt")
  puts "Latest prompt version: #{latest_prompt.version}"

  # Get with label
  labeled_prompt = client.get_prompt("greeting-prompt", label: "production")
  puts "Labeled prompt: #{labeled_prompt.labels}"

rescue Langfuse::APIError => e
  puts "Could not retrieve versioned prompt: #{e.message}"
end

# Example 5: Using prompts in tracing
puts "\n🔗 Example 5: Using prompts in tracing"

begin
  # Get a prompt for use in generation
  system_prompt = client.get_prompt("ai-assistant-chat")

  # Create a trace
  trace = client.trace(
    name: "prompt-based-chat",
    user_id: "user-789",
    input: { message: "Explain Ruby blocks" }
  )

  # Compile the prompt
  messages = system_prompt.compile(
    domain: "Ruby programming",
    tone: "educational and clear",
    detail_level: "beginner-friendly",
    user_message: "Explain Ruby blocks"
  )

  # Create generation with prompt
  generation = trace.generation(
    name: "openai-chat-with-prompt",
    model: "gpt-3.5-turbo",
    input: messages,
    output: {
      content: "Ruby blocks are pieces of code that can be passed to methods. They're defined using either do...end or curly braces {}. Blocks are commonly used with iterators like .each, .map, and .select."
    },
    usage: {
      prompt_tokens: 45,
      completion_tokens: 35,
      total_tokens: 80
    },
    metadata: {
      prompt_name: system_prompt.name,
      prompt_version: system_prompt.version
    }
  )

  puts "Created generation with prompt: #{generation.id}"
  puts "Trace URL: #{trace.get_url}"

rescue Langfuse::APIError => e
  puts "Could not use prompt in tracing: #{e.message}"
end

# Example 6: Advanced prompt features
puts "\n🎯 Example 6: Advanced prompt features"

# Create a prompt with complex templating
begin
  complex_prompt = client.create_prompt(
    name: "code-review-prompt",
    prompt: {
      system: "You are a senior {{language}} developer reviewing code. Focus on {{review_aspects}}.",
      user: "Please review this {{language}} code:\n\n```{{language}}\n{{code}}\n```\n\nProvide feedback on: {{specific_feedback}}"
    },
    labels: ["code-review", "development"],
    config: {
      temperature: 0.3,
      max_tokens: 500
    }
  )

  puts "Created complex prompt: #{complex_prompt.name}"

rescue Langfuse::APIError => e
  puts "Note: Complex prompt might already exist - #{e.message}"
end

# Create a prompt with conditional logic (using Ruby)
class ConditionalPrompt
  def self.generate(user_level:, topic:, include_examples: true)
    base_prompt = "Explain {{topic}} for a {{user_level}} audience."

    if include_examples
      base_prompt += " Include practical examples."
    end

    if user_level == "beginner"
      base_prompt += " Use simple language and avoid jargon."
    elsif user_level == "advanced"
      base_prompt += " Feel free to use technical terminology."
    end

    base_prompt
  end
end

conditional_prompt_text = ConditionalPrompt.generate(
  user_level: "beginner",
  topic: "machine learning",
  include_examples: true
)

puts "Conditional prompt: #{conditional_prompt_text}"

# Use with template
conditional_template = Langfuse::PromptTemplate.from_template(conditional_prompt_text)
formatted_prompt = conditional_template.format(
  topic: "neural networks",
  user_level: "beginner"
)

puts "Formatted conditional prompt: #{formatted_prompt}"

# Flush events
puts "\n🔄 Flushing events..."
client.flush

puts "\n✅ Prompt management example completed!"
puts "Check your Langfuse dashboard to see the prompts and traces."

# Shutdown client
client.shutdown
