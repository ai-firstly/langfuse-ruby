# frozen_string_literal: true

module Langfuse
  # Update events carry only the fields that changed. The ingestion API merges an
  # update into the existing trace/observation, so re-sending a generation's
  # input on every `end` call would double the payload of every LLM call.
  module PartialUpdates
    # Always sent so the server can resolve (and if needed upsert) the entity.
    # `to_dict#slice` ignores the keys a given class does not have.
    UPDATE_IDENTITY_FIELDS = %i[id trace_id type].freeze

    private

    # `changes` maps a body field to the value passed to update/end; nil means
    # "not provided" and is left out of the update body. `extra_keys` carries the
    # caller's **kwargs, which are merged into the body by to_dict.
    def track_changes(changes, extra_keys = nil)
      keys = changes.compact.keys
      keys.concat(extra_keys.to_a)
      @changed_fields = keys
    end

    def update_body
      # Never tracked → this is a create path; use the full body.
      return to_dict if @changed_fields.nil?

      to_dict.slice(*UPDATE_IDENTITY_FIELDS, *@changed_fields)
    end
  end
end
