# frozen_string_literal: true

module Langfuse
  class Span
    include PartialUpdates

    attr_reader :id, :trace_id, :name, :start_time, :end_time, :input, :output,
                :metadata, :level, :status_message, :parent_observation_id, :version,
                :as_type, :client

    def initialize(client:, trace_id:, id: nil, name: nil, start_time: nil, end_time: nil,
                   input: nil, output: nil, metadata: nil, level: nil, status_message: nil,
                   parent_observation_id: nil, version: nil, as_type: nil, **kwargs)
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
      @as_type = validate_as_type(as_type)
      @kwargs = kwargs

      # Create the span
      create_span
    end

    def update(name: nil, end_time: nil, input: nil, output: nil, metadata: nil,
               level: nil, status_message: nil, version: nil, **kwargs)
      @name = name unless name.nil?
      @end_time = end_time unless end_time.nil?
      @input = input unless input.nil?
      @output = output unless output.nil?
      @metadata.merge!(metadata) if metadata
      @level = level unless level.nil?
      @status_message = status_message unless status_message.nil?
      @version = version unless version.nil?
      @kwargs.merge!(kwargs)

      track_changes(
        { name: name, end_time: end_time, input: input, output: output,
          metadata: metadata, level: level, status_message: status_message,
          version: version },
        kwargs.keys
      )
      update_span
      self
    end

    def end(output: nil, end_time: nil, **kwargs)
      @end_time = end_time || Utils.current_timestamp
      @output = output unless output.nil?
      @kwargs.merge!(kwargs)

      track_changes({ end_time: @end_time, output: output }, kwargs.keys)
      update_span
      self
    end

    # Create a child span
    def span(name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
             metadata: nil, level: nil, status_message: nil, version: nil, as_type: nil, **kwargs)
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
        as_type: as_type,
        **kwargs
      )
    end

    # Create a child generation
    def generation(name: nil, start_time: nil, end_time: nil, completion_start_time: nil,
                   model: nil, model_parameters: nil, input: nil, output: nil, usage: nil,
                   usage_details: nil, cost_details: nil, prompt: nil,
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
        usage_details: usage_details,
        cost_details: cost_details,
        prompt: prompt,
        metadata: metadata,
        level: level,
        status_message: status_message,
        parent_observation_id: @id,
        version: version,
        **kwargs
      )
    end

    # Create a child event
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

    # Convenience methods for enhanced observation types: each is a child span
    # with a fixed as_type. (embedding keeps its own definition because it folds
    # model/usage into metadata first.)
    extend SpanWrappers
    define_span_wrappers

    # Create a child embedding observation
    def embedding(name: nil, start_time: nil, end_time: nil, input: nil, output: nil,
                  model: nil, usage: nil, metadata: nil, level: nil, status_message: nil,
                  version: nil, **kwargs)
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
        version: version,
        as_type: ObservationType::EMBEDDING,
        **kwargs
      )
    end

    def score(name:, value:, data_type: nil, comment: nil, **kwargs)
      @client.score(
        trace_id: @trace_id,
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
      }
      data[:type] = @as_type if @as_type
      data.merge(@kwargs).compact
    end

    private

    def validate_as_type(type)
      return nil if type.nil?

      type_str = type.to_s
      raise ValidationError, "Invalid observation type: #{type}. Valid types are: #{ObservationType::ALL.join(', ')}" unless ObservationType.valid?(type_str)

      type_str
    end

    def create_span
      @client.enqueue_event('span-create', to_dict)
    end

    def update_span
      @client.enqueue_event('span-update', update_body)
    end
  end
end
