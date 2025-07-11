require_relative '../spec_helper'

RSpec.describe Langfuse::Client do
  let(:client) do
    Langfuse::Client.new(
      public_key: "test_key",
      secret_key: "test_secret",
      host: "https://test.langfuse.com"
    )
  end

  describe "#initialize" do
    it "initializes with provided credentials" do
      expect(client.public_key).to eq("test_key")
      expect(client.secret_key).to eq("test_secret")
      expect(client.host).to eq("https://test.langfuse.com")
    end

    it "raises error without public key" do
      expect {
        Langfuse::Client.new(secret_key: "test_secret")
      }.to raise_error(Langfuse::AuthenticationError, "Public key is required")
    end

    it "raises error without secret key" do
      expect {
        Langfuse::Client.new(public_key: "test_key")
      }.to raise_error(Langfuse::AuthenticationError, "Secret key is required")
    end
  end

  describe "#trace" do
    it "creates a new trace" do
      trace = client.trace(name: "test_trace")

      expect(trace).to be_a(Langfuse::Trace)
      expect(trace.name).to eq("test_trace")
      expect(trace.id).not_to be_nil
    end
  end

  describe "#span" do
    it "creates a new span" do
      span = client.span(trace_id: "test_trace_id", name: "test_span")

      expect(span).to be_a(Langfuse::Span)
      expect(span.name).to eq("test_span")
      expect(span.trace_id).to eq("test_trace_id")
    end
  end

  describe "#generation" do
    it "creates a new generation" do
      generation = client.generation(
        trace_id: "test_trace_id",
        name: "test_generation",
        model: "gpt-3.5-turbo"
      )

      expect(generation).to be_a(Langfuse::Generation)
      expect(generation.name).to eq("test_generation")
      expect(generation.model).to eq("gpt-3.5-turbo")
    end
  end

  describe "#score" do
    it "creates a score" do
      expect(client).to receive(:enqueue_event).with('score-create', hash_including(
        name: "test_score",
        value: 0.8,
        trace_id: "test_trace_id"
      ))

      client.score(
        trace_id: "test_trace_id",
        name: "test_score",
        value: 0.8
      )
    end
  end

  describe "#flush" do
    it "flushes events when queue is not empty" do
      client.instance_variable_set(:@event_queue, [{ id: "test", type: "test", body: {} }])

      expect(client).to receive(:post).with("/api/public/ingestion", hash_including(:batch))

      client.flush
    end

    it "does nothing when queue is empty" do
      client.instance_variable_set(:@event_queue, [])

      expect(client).not_to receive(:post)

      client.flush
    end
  end
end
