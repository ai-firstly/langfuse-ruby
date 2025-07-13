module Langfuse
  class Event
    attr_reader :id, :trace_id, :name, :start_time, :input, :output, :metadata,
                :level, :status_message, :parent_observation_id, :version, :client

    def initialize(client:, trace_id:, name:, id: nil, start_time: nil, input: nil,
                   output: nil, metadata: nil, level: nil, status_message: nil,
                   parent_observation_id: nil, version: nil, **kwargs)
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
      @kwargs = kwargs

      # Create the event
      create_event
    end

    def to_dict
      {
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
      }.merge(@kwargs).compact
    end

    private

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
      }.merge(@kwargs).compact

      @client.enqueue_event('event-create', data)
    end
  end
end
