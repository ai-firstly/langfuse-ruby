# frozen_string_literal: true

module Langfuse
  class Generation
    attr_reader :id, :trace_id, :name, :start_time, :end_time, :completion_start_time,
                :model, :model_parameters, :input, :output, :usage, :metadata, :level,
                :status_message, :parent_observation_id, :version, :client

    def initialize(client:, trace_id:, id: nil, name: nil, start_time: nil, end_time: nil,
                   completion_start_time: nil, model: nil, model_parameters: nil, input: nil,
                   output: nil, usage: nil, metadata: nil, level: nil, status_message: nil,
                   parent_observation_id: nil, version: nil, **kwargs)
      @client = client
      @id = id || Utils.generate_id
      @trace_id = trace_id
      @name = name
      @start_time = start_time
      @end_time = end_time
      @completion_start_time = completion_start_time
      @model = model
      @model_parameters = model_parameters || {}
      @input = input
      @output = output
      @usage = usage || {}
      @metadata = metadata || {}
      @level = level
      @status_message = status_message
      @parent_observation_id = parent_observation_id
      @version = version
      @kwargs = kwargs

      # Create the generation
      create_generation
    end

    def update(name: nil, end_time: nil, completion_start_time: nil, model: nil,
               model_parameters: nil, input: nil, output: nil, usage: nil, metadata: nil,
               level: nil, status_message: nil, version: nil, **kwargs)
      @name = name if name
      @end_time = end_time if end_time
      @completion_start_time = completion_start_time if completion_start_time
      @model = model if model
      @model_parameters.merge!(model_parameters) if model_parameters
      @input = input if input
      @output = output if output
      @usage.merge!(usage) if usage
      @metadata.merge!(metadata) if metadata
      @level = level if level
      @status_message = status_message if status_message
      @version = version if version
      @kwargs.merge!(kwargs)

      update_generation
      self
    end

    def end(output: nil, end_time: nil, usage: nil, **kwargs)
      @end_time = end_time || Utils.current_timestamp
      @output = output if output
      @usage.merge!(usage) if usage
      @kwargs.merge!(kwargs)

      update_generation
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

    def event(name:, start_time: nil, input: nil, output: nil, metadata: nil,
              level: nil, status_message: nil, version: nil, **kwargs)
      @client.event(
        trace_id: @trace_id,
        name: name,
        start_time: start_time,
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
        completion_start_time: @completion_start_time,
        model: @model,
        model_parameters: @model_parameters,
        input: @input,
        output: @output,
        usage: @usage,
        metadata: @metadata,
        level: @level,
        status_message: @status_message,
        parent_observation_id: @parent_observation_id,
        version: @version
      }.merge(@kwargs).compact
    end

    private

    def create_generation
      @client.enqueue_event('generation-create', to_dict)
    end

    def update_generation
      @client.enqueue_event('generation-update', to_dict)
    end
  end
end
