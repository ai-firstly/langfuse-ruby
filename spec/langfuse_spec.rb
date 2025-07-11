RSpec.describe Langfuse do
  it "has a version number" do
    expect(Langfuse::VERSION).not_to be nil
  end

  describe ".configure" do
    it "allows configuration" do
      Langfuse.configure do |config|
        config.public_key = "test_key"
        config.secret_key = "test_secret"
        config.host = "https://test.langfuse.com"
      end

      expect(Langfuse.configuration.public_key).to eq("test_key")
      expect(Langfuse.configuration.secret_key).to eq("test_secret")
      expect(Langfuse.configuration.host).to eq("https://test.langfuse.com")
    end
  end

  describe ".new" do
    it "creates a new client instance" do
      client = Langfuse.new(
        public_key: "test_key",
        secret_key: "test_secret"
      )

      expect(client).to be_a(Langfuse::Client)
      expect(client.public_key).to eq("test_key")
      expect(client.secret_key).to eq("test_secret")
    end
  end
end
