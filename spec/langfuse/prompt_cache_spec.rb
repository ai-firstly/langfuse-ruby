# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::PromptCache do
  subject(:cache) { described_class.new }

  it 'returns nil for keys that were never written' do
    expect(cache.read('missing', 60)).to be_nil
    expect(cache.read_stale('missing')).to be_nil
  end

  it 'serves fresh entries and returns the prompt from #write' do
    expect(cache.write('k', :prompt)).to be(:prompt)
    expect(cache.read('k', 60)).to be(:prompt)
  end

  it 'expires entries by TTL on the monotonic clock' do
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1_000.0)
    cache.write('k', :prompt)

    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1_061.0)
    expect(cache.read('k', 60)).to be_nil
    expect(cache.read_stale('k')).to be(:prompt)
  end

  it 'evicts the oldest entries beyond max_entries' do
    bounded = described_class.new(max_entries: 2)
    bounded.write('a', :pa)
    bounded.write('b', :pb)
    bounded.write('c', :pc)

    expect(bounded.length).to eq(2)
    expect(bounded.read_stale('a')).to be_nil
    expect(bounded.read_stale('b')).to be(:pb)
    expect(bounded.read_stale('c')).to be(:pc)
  end

  it 're-writing a key refreshes its position without growing the cache' do
    bounded = described_class.new(max_entries: 2)
    bounded.write('a', :pa)
    bounded.write('b', :pb)
    bounded.write('a', :pa2)
    bounded.write('c', :pc)

    expect(bounded.length).to eq(2)
    expect(bounded.read_stale('b')).to be_nil
    expect(bounded.read_stale('a')).to be(:pa2)
    expect(bounded.read_stale('c')).to be(:pc)
  end

  it 'handles negative max_entries safely by treating it as 0' do
    bounded = described_class.new(max_entries: -1)
    bounded.write('a', :pa)

    expect(bounded.length).to eq(0)
  end

  it 'handles nil ttl_seconds gracefully without raising' do
    cache.write('a', :pa)

    expect(cache.read('a', nil)).to be_nil
  end
end
