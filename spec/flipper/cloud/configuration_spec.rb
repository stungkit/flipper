require 'helper'
require 'flipper/cloud/configuration'
require 'flipper/adapters/instrumented'

RSpec.describe Flipper::Cloud::Configuration do
  let(:required_options) do
    { token: "asdf" }
  end

  it "can set token" do
    instance = described_class.new(required_options)
    expect(instance.token).to eq(required_options[:token])
  end

  it "defaults url" do
    instance = described_class.new(required_options)
    expect(instance.url).to eq("https://www.featureflipper.com/adapter")
  end

  it "can set url" do
    options = required_options.merge(url: "http://localhost:5000/adapter")
    instance = described_class.new(options)
    expect(instance.url).to eq("http://localhost:5000/adapter")
  end

  it "can set read_timeout" do
    instance = described_class.new(required_options.merge(read_timeout: 5))
    expect(instance.read_timeout).to eq(5)
  end

  it "can set open_timeout" do
    instance = described_class.new(required_options.merge(open_timeout: 5))
    expect(instance.open_timeout).to eq(5)
  end

  it "can set instrumenter" do
    instrumenter = Object.new
    instance = described_class.new(required_options.merge(instrumenter: instrumenter))
    expect(instance.instrumenter).to be(instrumenter)
  end

  it "can set debug_output" do
    instance = described_class.new(required_options.merge(debug_output: STDOUT))
    expect(instance.debug_output).to eq(STDOUT)
  end

  it "can set sync_interval" do
    instance = described_class.new(required_options.merge(sync_interval: 1))
    expect(instance.sync_interval).to eq(1)
  end

  it "passes sync_interval into sync adapter" do
    # The initial sync of http to local invokes this web request.
    stub_request(:get, /featureflipper\.com/).to_return(status: 200, body: "{}")

    instance = described_class.new(required_options.merge(sync_interval: 1))
    expect(instance.adapter.synchronizer.interval).to be(1)
  end

  it 'defaults local_adapter' do
    instance = described_class.new(required_options)
    expect(instance.local_adapter).to be_instance_of(Flipper::Adapters::Memory)
  end

  it 'can set local_adapter' do
    local_adapter = Flipper::Adapters::Memory.new
    instance = described_class.new(required_options.merge(local_adapter: local_adapter))
    expect(instance.local_adapter).to be(local_adapter)
  end

  it "defaults adapter block" do
    # The initial sync of http to local invokes this web request.
    stub_request(:get, /featureflipper\.com/).to_return(status: 200, body: "{}")

    instance = described_class.new(required_options)
    expect(instance.adapter).to be_instance_of(Flipper::Adapters::Sync)
  end

  it "can override adapter block" do
    # The initial sync of http to local invokes this web request.
    stub_request(:get, /featureflipper\.com/).to_return(status: 200, body: "{}")

    instance = described_class.new(required_options)
    instance.adapter do |adapter|
      Flipper::Adapters::Instrumented.new(adapter)
    end
    expect(instance.adapter).to be_instance_of(Flipper::Adapters::Instrumented)
  end

  it "can set reporter_options" do
    reporter_options = {
      flush_interval: 60,
    }
    options = required_options.merge(reporter_options: reporter_options)
    instance = described_class.new(options)
    expect(instance.reporter_options[:flush_interval]).to eq(60)
  end

  it 'configures http client' do
    client_options = {
      url: "https://example.com",
      read_timeout: 99,
      open_timeout: 99,
      debug_output: STDOUT,
    }
    instance = described_class.new(required_options.merge(client_options))
    client = instance.client

    expect(client.url).to eq(client_options.fetch(:url))
    expect(client.read_timeout).to be(99)
    expect(client.open_timeout).to be(99)
    expect(client.debug_output).to be(STDOUT)

    expect(client.headers["FEATURE_FLIPPER_TOKEN"]).to eq(required_options.fetch(:token))
    expect(client.headers["FLIPPER_VERSION"]).to eq(Flipper::VERSION)
    expect(client.headers["FLIPPER_PLATFORM"]).to eq("ruby")
    expect(client.headers["FLIPPER_PLATFORM_VERSION"]).to eq(RUBY_VERSION)
    hostname = Socket.gethostbyname(Socket.gethostname).first
    expect(client.headers["FLIPPER_HOSTNAME"]).to eq(hostname)
    expect(client.headers["FLIPPER_PID"]).to eq(Process.pid.to_s)
    expect(client.headers["FLIPPER_THREAD"]).to eq(Thread.current.object_id.to_s)
  end

  it 'allows customizing client options' do
    client_options = {
      url: "https://example.com",
      read_timeout: 99,
      open_timeout: 99,
      debug_output: STDOUT,
    }
    instance = described_class.new(required_options.merge(client_options))
    client = instance.client(url: "https://customized.com")
    expect(client.url).to eq("https://customized.com")
  end
end
