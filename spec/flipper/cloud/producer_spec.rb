require "helper"
require "flipper/event"
require "flipper/cloud/configuration"
require "flipper/cloud/producer"
require "flipper/instrumenters/memory"

RSpec.describe Flipper::Cloud::Producer do
  let(:instrumenter) do
    Flipper::Instrumenters::Memory.new
  end

  let(:event) do
    attributes = {
      type: "enabled",
      dimensions: {
        "feature" => "foo",
        "flipper_id" => "User;23",
        "result" => "true",
      },
      timestamp: Flipper::Timestamp.generate,
    }
    Flipper::Event.new(attributes)
  end

  let(:configuration) do
    options = {
      token: "asdf",
      url: "https://www.featureflipper.com/adapter",
    }
    Flipper::Cloud::Configuration.new(options)
  end

  let(:client) { configuration.client }

  let(:producer_options) do
    {
      client: client,
      capacity: 10,
      batch_size: 5,
      flush_interval: 0.1,
      retry_strategy: Flipper::RetryStrategy.new(sleep: false),
      instrumenter: instrumenter,
      automatic_shutdown: false,
    }
  end

  subject do
    described_class.new(producer_options)
  end

  before do
    stub_request(:post, "https://www.featureflipper.com/adapter/events")
  end

  it 'creates thread on produce and kills on shutdown' do
    expect(subject.instance_variable_get("@worker_thread")).to be_nil
    expect(subject.instance_variable_get("@timer_thread")).to be_nil

    subject.produce(event)

    expect(subject.instance_variable_get("@worker_thread")).to be_instance_of(Thread)
    expect(subject.instance_variable_get("@timer_thread")).to be_instance_of(Thread)

    subject.shutdown

    sleep subject.flush_interval * 2

    expect(subject.instance_variable_get("@worker_thread")).not_to be_alive
    expect(subject.instance_variable_get("@timer_thread")).not_to be_alive
  end

  it 'can produce messages' do
    block = lambda do |request|
      data = JSON.parse(request.body)
      events = data.fetch("events")
      events.size == 5
    end

    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .with(&block)
      .to_return(status: 201)

    5.times { subject.produce(event) }
    subject.shutdown
  end

  it 'instruments event being discarded when queue is full' do
    instance = described_class.new(producer_options)
    instance.capacity.times do
      instance.queue << [:produce, event]
    end
    instance.produce event
    events = instrumenter.events_by_name("event_discarded.flipper")
    expect(events.size).to be(1)
  end

  it 'retries requests that error up to configured limit' do
    retry_strategy = Flipper::RetryStrategy.new(instrumenter: instrumenter, sleep: false)
    producer_options = {
      client: client,
      instrumenter: instrumenter,
      retry_strategy: retry_strategy,
    }
    instance = described_class.new(producer_options)

    exception = StandardError.new
    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .to_raise(exception)
    instance.produce(event)
    instance.shutdown

    events = instrumenter.events_by_name("exception.flipper")
    expect(events.size).to be(retry_strategy.limit)
  end

  it 'retries 5xx response statuses up to configured limit' do
    instrumenter.reset

    retry_strategy = Flipper::RetryStrategy.new(instrumenter: instrumenter, sleep: false)
    producer_options = {
      client: client,
      instrumenter: instrumenter,
      retry_strategy: retry_strategy,
    }
    instance = described_class.new(producer_options)

    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .to_return(status: 500)

    instance.produce(event)
    instance.shutdown

    events = instrumenter.events_by_name("exception.flipper")
    expect(events.size).to be(retry_strategy.limit)
  end

  it 'flushes at exit' do
    begin
      server = TestServer.new
      client = configuration.client(url: "http://localhost:#{server.port}")
      producer_options[:client] = client
      producer_options[:automatic_shutdown] = true
      producer = described_class.new(producer_options)

      pid = fork { producer.produce(event) }
      Process.waitpid pid, 0

      expect(server.event_receiver.size).to be(1)

      event_posts = server.access_lines.select { |line| line =~ %r{POST /events} }
      expect(event_posts.size).to be(1)
    ensure
      server.shutdown
    end
  end
end
