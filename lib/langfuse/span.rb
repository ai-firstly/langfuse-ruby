module Langfuse
  class Span
    attr_reader :id, :trace_id, :name, :start_time, :end_time, :input, :output,
                :metadata, :level, :status_message, :parent_observation_id, :version, :client

    def initialize(client:, trace_id:, id: nil, name: nil, start_time: nil, end_time: nil,
                   input: nil, output: nil, metadata: nil, level: nil, status_message: nil,
                   parent_observation_id: nil, version: nil, **kwargs)
      @client = client
      @id = id || Utils.generate_id
      @trace_id = trace_id
      @name = name
      @start_time = start_time
      @end_time = end_time
      @input = input
      @output = output
      @metadata = metadata || {}
      @level = level
      @status_message = status_message
      @parent_observation_id = parent_observation_id
      @version = version
      @kwargs = kwargs

      # Create the span
      create_span
    end

    def update(name: nil, end_time: nil, input: nil, output: nil, metadata: nil,
               level: nil, status_message: nil, version: nil, **kwargs)
      @name = name if name
      @end_time = end_time if end_time
      @input = input if input
      @output = output if output
      @metadata.merge!(metadata) if metadata
      @level = level if level
      @status_message = status_message if status_message
      @version = version if version
      @kwargs.merge!(kwargs)

      update_span
      self
    end

    def end(output: nil, end_time: nil, **kwargs)
      @end_time = end_time || Utils.current_timestamp
      @output = output if output
      @kwargs.merge!(kwargs)

      update_span
      self
    end

    def span(name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
             metadata: nil, level: nil, status_message: nil, version: nil, **kwargs)
      @client.span(
        trace_id: @trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: @id,
        version: version,
        **kwargs
      )
    end

    def generation(name: nil, start_time: nil, end_time: nil, completion_start_time: nil,
                   model: nil, model_parameters: nil, input: nil, output: nil, usage: nil,
                   metadata: nil, level: nil, status_message: nil, version: nil, **kwargs)
      @client.generation(
        trace_id: @trace_id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        completion_start_time: completion_start_time,
        model: model,
        model_parameters: model_parameters,
        input: input,
        output: output,
        usage: usage,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: @id,
        version: version,
        **kwargs
      )
    end

    def score(name:, value:, data_type: nil, comment: nil, **kwargs)
      @client.score(
        observation_id: @id,
        name: name,
        value: value,
        data_type: data_type,
        comment: comment,
        **kwargs
      )
    end

    def get_url
      "#{@client.host}/trace/#{@trace_id}?observation=#{@id}"
    end

    def to_dict
      {
        id: @id,
        trace_id: @trace_id,
        name: @name,
        start_time: @start_time,
        end_time: @end_time,
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

    def create_span
      data = {
        id: @id,
        trace_id: @trace_id,
        name: @name,
        start_time: @start_time,
        end_time: @end_time,
        input: @input,
        output: @output,
        metadata: @metadata,
        level: @level,
        status_message: @status_message,
        parent_observation_id: @parent_observation_id,
        version: @version
      }.merge(@kwargs).compact

      @client.enqueue_event('span-create', data)
    end

    def update_span
      data = {
        id: @id,
        trace_id: @trace_id,
        name: @name,
        start_time: @start_time,
        end_time: @end_time,
        input: @input,
        output: @output,
        metadata: @metadata,
        level: @level,
        status_message: @status_message,
        parent_observation_id: @parent_observation_id,
        version: @version
      }.merge(@kwargs).compact

      @client.enqueue_event('span-update', data)
    end
  end
end
