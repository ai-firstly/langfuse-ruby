# frozen_string_literal: true

module Langfuse
  class Event
    attr_reader :id, :trace_id, :name, :start_time, :input, :output, :metadata,
                :level, :status_message, :parent_observation_id, :version, :as_type, :client

    def initialize(client:, trace_id:, name:, id: nil, start_time: nil, input: nil,
                   output: nil, metadata: nil, level: nil, status_message: nil,
                   parent_observation_id: nil, version: nil, as_type: nil, **kwargs)
      @client = client
      @id = id || Utils.generate_id
      @trace_id = trace_id
      @name = name
      @start_time = start_time || Utils.current_timestamp
      @input = input
      @output = output
      @metadata = metadata || {}
      @level = level
      @status_message = status_message
      @parent_observation_id = parent_observation_id
      @version = version
      @as_type = validate_as_type(as_type)
      @kwargs = kwargs

      # Create the event
      create_event
    end

    def to_dict
      data = {
        id: @id,
        trace_id: @trace_id,
        name: @name,
        start_time: @start_time,
        input: @input,
        output: @output,
        metadata: @metadata,
        level: @level,
        status_message: @status_message,
        parent_observation_id: @parent_observation_id,
        version: @version
      }
      data[:type] = @as_type if @as_type
      data.merge(@kwargs).compact
    end

    private

    def validate_as_type(type)
      return nil if type.nil?

      type_str = type.to_s
      unless ObservationType.valid?(type_str)
        raise ValidationError, "Invalid observation type: #{type}. Valid types are: #{ObservationType::ALL.join(', ')}"
      end

      type_str
    end

    def create_event
      data = {
        id: @id,
        trace_id: @trace_id,
        name: @name,
        start_time: @start_time,
        input: @input,
        output: @output,
        metadata: @metadata,
        level: @level,
        status_message: @status_message,
        parent_observation_id: @parent_observation_id,
        version: @version
      }
      data[:type] = @as_type if @as_type
      data = data.merge(@kwargs).compact

      @client.enqueue_event('event-create', data)
    end
  end
end
