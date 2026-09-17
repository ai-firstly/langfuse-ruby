# frozen_string_literal: true

module Langfuse
  class Trace
    include PartialUpdates

    attr_reader :id, :name, :user_id, :session_id, :version, :release, :input, :output,
                :metadata, :tags, :timestamp, :public, :client

    def initialize(client:, id:, name: nil, user_id: nil, session_id: nil, version: nil,
                   release: nil, input: nil, output: nil, metadata: nil, tags: nil,
                   timestamp: nil, public: nil, **kwargs)
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
      @public = public
      @kwargs = kwargs

      # Create the trace
      create_trace
    end

    # Create a child span with optional type
    def span(name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
             metadata: nil, level: nil, status_message: nil, parent_observation_id: nil,
             version: nil, as_type: nil, **kwargs)
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
        as_type: as_type,
        **kwargs
      )
    end

    # Create a child generation
    def generation(name: nil, start_time: nil, end_time: nil, completion_start_time: nil,
                   model: nil, model_parameters: nil, input: nil, output: nil, usage: nil,
                   usage_details: nil, cost_details: nil, prompt: nil,
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
        usage_details: usage_details,
        cost_details: cost_details,
        prompt: prompt,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        **kwargs
      )
    end

    # Create a child event
    def event(name:, start_time: nil, input: nil, output: nil, metadata: nil,
              level: nil, status_message: nil, parent_observation_id: nil, version: nil, **kwargs)
      @client.event(
        trace_id: @id,
        name: name,
        start_time: start_time,
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

    # Convenience methods for enhanced observation types: each is a child span
    # with a fixed as_type. (embedding keeps its own definition because it folds
    # model/usage into metadata first.)
    extend SpanWrappers
    define_span_wrappers

    # Create a child embedding observation
    def embedding(name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
                  model: nil, usage: nil, metadata: nil, level: nil, status_message: nil,
                  parent_observation_id: nil, version: nil, **kwargs)
      merged_metadata = (metadata || {}).merge(
        { model: model, usage: usage }.compact
      )
      span(
        name: name,
        start_time: start_time,
        end_time: end_time,
        input: input,
        output: output,
        metadata: merged_metadata.empty? ? nil : merged_metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: parent_observation_id,
        version: version,
        as_type: ObservationType::EMBEDDING,
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

    def update(name: nil, user_id: nil, session_id: nil, version: nil,
               release: nil, input: nil, output: nil, metadata: nil, tags: nil,
               public: nil, **kwargs)
      # 更新实例变量
      @name = name unless name.nil?
      @user_id = user_id unless user_id.nil?
      @session_id = session_id unless session_id.nil?
      @version = version unless version.nil?
      @release = release unless release.nil?
      @input = input unless input.nil?
      @output = output unless output.nil?
      @metadata.merge!(metadata) if metadata
      @tags = tags unless tags.nil?
      @public = public unless public.nil?
      @kwargs.merge!(kwargs) if kwargs.any?

      track_changes(
        { name: name, user_id: user_id, session_id: session_id, version: version,
          release: release, input: input, output: output, metadata: metadata,
          tags: tags, public: public },
        kwargs.keys
      )
      # 触发 trace-update 事件
      update_trace
      self
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
        timestamp: @timestamp,
        public: @public
      }.merge(@kwargs).compact
    end

    private

    def create_trace
      @client.enqueue_event('trace-create', to_dict)
    end

    def update_trace
      @client.enqueue_event('trace-update', update_body, trace_ref: self)
    end
  end
end
