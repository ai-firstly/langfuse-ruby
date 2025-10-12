# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Langfuse::Event do
  let(:client) { Langfuse::Client.new(public_key: 'test_key', secret_key: 'test_secret', debug: false) }
  let(:trace) { client.trace(name: 'test-trace') }
  let(:span) { trace.span(name: 'test-span') }
  let(:event) { trace.event(name: 'test-event', input: { action: 'click' }) }

  describe 'initialization' do
    it 'creates an event with basic attributes' do
      expect(event).to be_a(Langfuse::Event)
      expect(event.name).to eq('test-event')
      expect(event.input).to eq({ action: 'click' })
      expect(event.trace_id).to eq(trace.id)
      expect(event.id).not_to be_nil
    end

    it 'creates an event within a span' do
      span_event = span.event(
        name: 'span-event',
        input: { operation: 'process_data' },
        output: { result: 'success' }
      )

      expect(span_event).to be_a(Langfuse::Event)
      expect(span_event.name).to eq('span-event')
      expect(span_event.trace_id).to eq(trace.id)
      expect(span_event.input).to eq({ operation: 'process_data' })
      expect(span_event.output).to eq({ result: 'success' })
    end

    it 'creates an event directly with trace_id' do
      direct_event = client.event(
        trace_id: 'test-trace-id',
        name: 'direct-event',
        input: { type: 'custom' }
      )

      expect(direct_event.trace_id).to eq('test-trace-id')
      expect(direct_event.name).to eq('direct-event')
    end
  end

  describe 'event attributes' do
    it 'supports various event attributes' do
      detailed_event = trace.event(
        name: 'detailed-event',
        input: {
          user_id: 'user-123',
          action: 'purchase',
          item_id: 'item-456',
          quantity: 2,
          price: 99.99
        },
        output: {
          status: 'completed',
          transaction_id: 'txn-789'
        },
        metadata: {
          source: 'web',
          browser: 'chrome',
          version: '1.0.0'
        },
        level: 'INFO'
      )

      expect(detailed_event.name).to eq('detailed-event')
      expect(detailed_event.input[:user_id]).to eq('user-123')
      expect(detailed_event.output[:status]).to eq('completed')
      expect(detailed_event.metadata[:source]).to eq('web')
      expect(detailed_event.level).to eq('INFO')
    end
  end

  describe 'event types' do
    it 'handles user interaction events' do
      user_event = trace.event(
        name: 'user-click',
        input: {
          element: 'submit-button',
          page: '/checkout',
          timestamp: Time.now.iso8601
        },
        metadata: {
          user_agent: 'Mozilla/5.0...',
          session_id: 'session-123'
        }
      )

      expect(user_event.name).to eq('user-click')
      expect(user_event.input[:element]).to eq('submit-button')
    end

    it 'handles system events' do
      system_event = trace.event(
        name: 'system-alert',
        input: {
          alert_type: 'performance',
          metric: 'response_time',
          value: 2.5,
          threshold: 1.0
        },
        output: {
          action_taken: 'scale_up',
          new_instances: 2
        },
        level: 'WARNING'
      )

      expect(system_event.name).to eq('system-alert')
      expect(system_event.input[:alert_type]).to eq('performance')
      expect(system_event.level).to eq('WARNING')
    end

    it 'handles business events' do
      business_event = trace.event(
        name: 'order-completed',
        input: {
          order_id: 'order-123',
          customer_id: 'customer-456',
          total_amount: 299.99,
          items: ['item-1', 'item-2']
        },
        output: {
          confirmation_sent: true,
          fulfillment_started: true
        },
        metadata: {
          payment_method: 'credit_card',
          shipping_method: 'express'
        }
      )

      expect(business_event.name).to eq('order-completed')
      expect(business_event.input[:order_id]).to eq('order-123')
      expect(business_event.output[:confirmation_sent]).to be true
    end
  end

  describe 'event timing' do
    it 'records event timestamps' do
      timestamp = Time.now.iso8601
      timed_event = trace.event(
        name: 'timed-event',
        input: { operation: 'backup' },
        timestamp: timestamp
      )

      expect(timed_event.name).to eq('timed-event')
    end
  end

  describe 'complex event workflows' do
    it 'supports event chains within a trace' do
      # Start event
      start_event = trace.event(
        name: 'workflow-started',
        input: { workflow_id: 'wf-123', user_id: 'user-456' }
      )

      # Step events
      step1_event = trace.event(
        name: 'step-1-completed',
        input: { step_id: 'step-1', duration: 1.2 },
        output: { status: 'success', result: 'processed' }
      )

      step2_event = trace.event(
        name: 'step-2-completed',
        input: { step_id: 'step-2', duration: 0.8 },
        output: { status: 'success', result: 'validated' }
      )

      # End event
      end_event = trace.event(
        name: 'workflow-completed',
        input: { workflow_id: 'wf-123', total_duration: 2.0 },
        output: { final_status: 'completed', artifacts: ['file-1', 'file-2'] }
      )

      expect(start_event.name).to eq('workflow-started')
      expect(step1_event.name).to eq('step-1-completed')
      expect(step2_event.name).to eq('step-2-completed')
      expect(end_event.name).to eq('workflow-completed')

      # All events should belong to the same trace
      expect(start_event.trace_id).to eq(trace.id)
      expect(step1_event.trace_id).to eq(trace.id)
      expect(step2_event.trace_id).to eq(trace.id)
      expect(end_event.trace_id).to eq(trace.id)
    end
  end

  describe 'event with errors' do
    it 'handles error events' do
      error_event = trace.event(
        name: 'error-occurred',
        input: {
          operation: 'database_query',
          query: 'SELECT * FROM users'
        },
        output: {
          error_type: 'DatabaseError',
          error_message: 'Connection timeout',
          stack_trace: 'at line 42 in query_executor.rb'
        },
        level: 'ERROR'
      )

      expect(error_event.name).to eq('error-occurred')
      expect(error_event.output[:error_type]).to eq('DatabaseError')
      expect(error_event.level).to eq('ERROR')
    end
  end

  describe 'event updates' do
    it 'updates event attributes' do
      expect(client).to receive(:enqueue_event).with('event-update', hash_including(
        id: event.id,
        output: { updated_result: 'modified' }
      ))

      event.update(output: { updated_result: 'modified' })
    end

    it 'updates event with additional metadata' do
      expect(client).to receive(:enqueue_event).with('event-update', hash_including(
        id: event.id,
        metadata: { additional_info: 'updated' }
      ))

      event.update(metadata: { additional_info: 'updated' })
    end
  end
end