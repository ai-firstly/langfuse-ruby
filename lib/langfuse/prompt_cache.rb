# frozen_string_literal: true

require 'concurrent'

module Langfuse
  # Bounded, thread-safe cache of Prompt objects, keyed by name/version/label.
  #
  # TTLs are measured on the monotonic clock so wall-clock jumps (NTP, DST) cannot
  # extend or shorten an entry's lifetime. Entries keep insertion order and the
  # oldest ones are evicted once the cache is full, so a long-running process with
  # many prompt names cannot grow it without bound.
  class PromptCache
    DEFAULT_MAX_ENTRIES = 200

    Entry = Struct.new(:prompt, :cached_at) do
      def fresh?(ttl_seconds, now)
        return false if ttl_seconds.nil?

        now - cached_at < ttl_seconds
      end
    end

    def initialize(max_entries: DEFAULT_MAX_ENTRIES)
      @max_entries = [max_entries.to_i, 0].max
      @entries = Concurrent::Hash.new
      @mutex = Mutex.new
    end

    # The cached prompt while it is still fresh, otherwise nil.
    def read(key, ttl_seconds)
      entry = @entries[key]
      return nil unless entry&.fresh?(ttl_seconds, monotonic_time)

      entry.prompt
    end

    # The cached prompt regardless of age. Used to keep serving prompts while the
    # Langfuse API is unreachable.
    def read_stale(key)
      @entries[key]&.prompt
    end

    # Writes are serialized so concurrent fetches cannot corrupt the hash while it
    # is being trimmed. Returns the prompt for convenient chaining.
    def write(key, prompt)
      @mutex.synchronize do
        @entries.delete(key)
        @entries[key] = Entry.new(prompt, monotonic_time)
        @entries.shift while @entries.length > @max_entries && !@entries.empty?
      end

      prompt
    end

    def length
      @entries.length
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
