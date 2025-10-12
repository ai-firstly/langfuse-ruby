# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Utils do
  describe '.generate_id' do
    it 'generates a unique ID' do
      id1 = described_class.generate_id
      id2 = described_class.generate_id

      expect(id1).to be_a(String)
      expect(id2).to be_a(String)
      expect(id1).not_to eq(id2)
    end

    it 'generates IDs with consistent length' do
      id = described_class.generate_id
      expect(id.length).to be > 0
      expect(id.length).to be < 100  # Reasonable upper bound
    end

    it 'generates valid UUID-like IDs' do
      id = described_class.generate_id
      # Should contain letters, numbers, and possibly hyphens
      expect(id).to match(/^[a-zA-Z0-9\-_]+$/)
    end
  end

  describe '.current_timestamp' do
    it 'returns current timestamp in ISO8601 format' do
      timestamp = described_class.current_timestamp

      expect(timestamp).to be_a(String)
      expect(timestamp).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(timestamp).to include('Z')
    end

    it 'returns different timestamps on subsequent calls' do
      timestamp1 = described_class.current_timestamp
      sleep(0.001)  # Small delay to ensure different timestamps
      timestamp2 = described_class.current_timestamp

      expect(timestamp1).not_to eq(timestamp2)
    end
  end

  describe '.deep_symbolize_keys' do
    it 'symbolizes string keys in a simple hash' do
      hash = { 'key1' => 'value1', 'key2' => 'value2' }
      result = described_class.deep_symbolize_keys(hash)

      expect(result).to eq({ key1: 'value1', key2: 'value2' })
    end

    it 'handles nested hashes' do
      hash = {
        'outer_key' => {
          'inner_key1' => 'inner_value1',
          'inner_key2' => {
            'deep_key' => 'deep_value'
          }
        }
      }

      result = described_class.deep_symbolize_keys(hash)
      expected = {
        outer_key: {
          inner_key1: 'inner_value1',
          inner_key2: {
            deep_key: 'deep_value'
          }
        }
      }

      expect(result).to eq(expected)
    end

    it 'handles arrays containing hashes' do
      hash = {
        'items' => [
          { 'id' => 1, 'name' => 'item1' },
          { 'id' => 2, 'name' => 'item2' }
        ]
      }

      result = described_class.deep_symbolize_keys(hash)
      expected = {
        items: [
          { id: 1, name: 'item1' },
          { id: 2, name: 'item2' }
        ]
      }

      expect(result).to eq(expected)
    end

    it 'handles mixed nested structures' do
      hash = {
        'users' => [
          {
            'id' => 1,
            'profile' => {
              'settings' => { 'theme' => 'dark' },
              'preferences' => ['notifications', 'emails']
            }
          }
        ],
        'metadata' => { 'version' => '1.0' }
      }

      result = described_class.deep_symbolize_keys(hash)
      expect(result[:users][0][:profile][:settings][:theme]).to eq('dark')
      expect(result[:metadata][:version]).to eq('1.0')
    end

    it 'leaves non-hash values unchanged' do
      hash = {
        'string' => 'value',
        'number' => 42,
        'boolean' => true,
        'nil_value' => nil,
        'array' => [1, 2, 3]
      }

      result = described_class.deep_symbolize_keys(hash)

      expect(result[:string]).to eq('value')
      expect(result[:number]).to eq(42)
      expect(result[:boolean]).to be true
      expect(result[:nil_value]).to be_nil
      expect(result[:array]).to eq([1, 2, 3])
    end

    it 'handles empty hashes and arrays' do
      hash = { 'empty_hash' => {}, 'empty_array' => [] }
      result = described_class.deep_symbolize_keys(hash)

      expect(result).to eq({ empty_hash: {}, empty_array: [] })
    end
  end

  describe '.deep_stringify_keys' do
    it 'stringifies symbol keys in a simple hash' do
      hash = { key1: 'value1', key2: 'value2' }
      result = described_class.deep_stringify_keys(hash)

      expect(result).to eq({ 'key1' => 'value1', 'key2' => 'value2' })
    end

    it 'handles nested hashes with symbol keys' do
      hash = {
        outer_key: {
          inner_key1: 'inner_value1',
          inner_key2: {
            deep_key: 'deep_value'
          }
        }
      }

      result = described_class.deep_stringify_keys(hash)
      expected = {
        'outer_key' => {
          'inner_key1' => 'inner_value1',
          'inner_key2' => {
            'deep_key' => 'deep_value'
          }
        }
      }

      expect(result).to eq(expected)
    end

    it 'handles arrays containing hashes with symbol keys' do
      hash = {
        items: [
          { id: 1, name: 'item1' },
          { id: 2, name: 'item2' }
        ]
      }

      result = described_class.deep_stringify_keys(hash)
      expected = {
        'items' => [
          { 'id' => 1, 'name' => 'item1' },
          { 'id' => 2, 'name' => 'item2' }
        ]
      }

      expect(result).to eq(expected)
    end

    it 'handles mixed key types' do
      hash = {
        'string_key' => 'value1',
        symbol_key: 'value2',
        nested: {
          'mixed_string' => 'nested1',
          mixed_symbol: 'nested2'
        }
      }

      result = described_class.deep_stringify_keys(hash)
      expected = {
        'string_key' => 'value1',
        'symbol_key' => 'value2',
        'nested' => {
          'mixed_string' => 'nested1',
          'mixed_symbol' => 'nested2'
        }
      }

      expect(result).to eq(expected)
    end

    it 'leaves non-hash values unchanged' do
      hash = {
        string: 'value',
        number: 42,
        boolean: true,
        nil_value: nil,
        array: [1, 2, 3]
      }

      result = described_class.deep_stringify_keys(hash)

      expect(result['string']).to eq('value')
      expect(result['number']).to eq(42)
      expect(result['boolean']).to be true
      expect(result['nil_value']).to be_nil
      expect(result['array']).to eq([1, 2, 3])
    end
  end

  describe 'round-trip conversion' do
    it 'maintains data integrity through symbolize -> stringify conversion' do
      original = {
        'users' => [
          {
            'id' => 1,
            'profile' => {
              'settings' => { 'theme' => 'dark' }
            }
          }
        ]
      }

      symbolized = described_class.deep_symbolize_keys(original)
      stringified = described_class.deep_stringify_keys(symbolized)

      expect(stringified).to eq(original)
    end

    it 'maintains data integrity through stringify -> symbolize conversion' do
      original = {
        users: [
          {
            id: 1,
            profile: {
              settings: { theme: 'dark' }
            }
          }
        ]
      }

      stringified = described_class.deep_stringify_keys(original)
      symbolized = described_class.deep_symbolize_keys(stringified)

      expect(symbolized).to eq(original)
    end
  end
end