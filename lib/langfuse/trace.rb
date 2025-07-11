module Langfuse
  class Trace
    attr_reader :id, :name, :user_id, :session_id, :version, :release, :input, :output,
                :metadata, :tags, :timestamp, :client

    def initialize(client:, id:, name: nil, user_id: nil, session_id: nil, version: nil,
                   release: nil, input: nil, output: nil, metadata: nil, tags: nil,
                   timestamp: nil, **kwargs)
      @client = client
      @id = id
      @name = name
      @user_id = user_id
      @session_id = session_id
      @version = version
      @release = release
      @input = input
      @output = output
      @metadata = metadata || {}
      @tags = tags || []
      @timestamp = timestamp
      @kwargs = kwargs

      # Create the trace
      create_trace
    end

    def update(name: nil, user_id: nil, session_id: nil, version: nil, release: nil,
               input: nil, output: nil, metadata: nil, tags: nil, **kwargs)
      @name = name if name
      @user_id = user_id if user_id
      @session_id = session_id if session_id
      @version = version if version
      @release = release if release
      @input = input if input
      @output = output if output
      @metadata.merge!(metadata) if metadata
      @tags.concat(tags) if tags
      @kwargs.merge!(kwargs)

      update_trace
      self
    end

    def span(name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
             metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
             version: nil, **kwargs)
      @client.span(
        trace_id: @id,
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        **kwargs
      )
    end

    def generation(name: nil, start_time: nil, end_time: nil, completion_start_time: nil,
                   model: nil, model_parameters: nil, input: nil, output: nil, usage: nil,
                   metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
                   version: nil, **kwargs)
      @client.generation(
        trace_id: @id,
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
        parent_observation_id: parent_observation_id,
        version: version,
        **kwargs
      )
    end

    def score(name:, value:, data_type: nil, comment: nil, **kwargs)
      @client.score(
        trace_id: @id,
        name: name,
        value: value,
        data_type: data_type,
        comment: comment,
        **kwargs
      )
    end

    def get_url
      "#{@client.host}/trace/#{@id}"
    end

    def to_dict
      {
        id: @id,
        name: @name,
        user_id: @user_id,
        session_id: @session_id,
        version: @version,
        release: @release,
        input: @input,
        output: @output,
        metadata: @metadata,
        tags: @tags,
        timestamp: @timestamp
      }.merge(@kwargs).compact
    end

    private

    def create_trace
      data = {
        id: @id,
        name: @name,
        user_id: @user_id,
        session_id: @session_id,
        version: @version,
        release: @release,
        input: @input,
        output: @output,
        metadata: @metadata,
        tags: @tags,
        timestamp: @timestamp
      }.merge(@kwargs).compact

      @client.enqueue_event('trace-create', data)
    end

    def update_trace
      data = {
        id: @id,
        name: @name,
        user_id: @user_id,
        session_id: @session_id,
        version: @version,
        release: @release,
        input: @input,
        output: @output,
        metadata: @metadata,
        tags: @tags
      }.merge(@kwargs).compact

      @client.enqueue_event('trace-update', data)
    end
  end
end
