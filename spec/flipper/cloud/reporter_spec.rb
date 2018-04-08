require "helper"
require "flipper/event"
require "flipper/cloud/configuration"
require "flipper/cloud/reporter"
require "flipper/instrumenters/memory"

RSpec.describe Flipper::Cloud::Reporter do
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

  let(:reporter_options) do
    {
      client: client,
      capacity: 10,
      batch_size: 5,
      flush_interval: 0.1,
      retry_strategy: Flipper::RetryStrategy.new(sleep: false),
      instrumenter: instrumenter,
      shutdown_automatically: false,
    }
  end

  subject do
    described_class.new(reporter_options)
  end

  before do
    stub_request(:post, "https://www.featureflipper.com/adapter/events")
  end

  it 'creates thread on reporter and kills on shutdown' do
    expect(subject.instance_variable_get("@worker_thread")).to be_nil
    expect(subject.instance_variable_get("@timer_thread")).to be_nil

    subject.report(event)

    expect(subject.instance_variable_get("@worker_thread")).to be_instance_of(Thread)
    expect(subject.instance_variable_get("@timer_thread")).to be_instance_of(Thread)

    subject.shutdown

    sleep subject.flush_interval * 2

    expect(subject.instance_variable_get("@worker_thread")).not_to be_alive
    expect(subject.instance_variable_get("@timer_thread")).not_to be_alive
  end

  it 'can report messages' do
    block = lambda do |request|
      data = JSON.parse(request.body)
      events = data.fetch("events")
      events.size == 5
    end

    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .with(&block)
      .to_return(status: 201)

    5.times { subject.report(event) }
    subject.shutdown
  end

  it 'instruments event being discarded when queue is full' do
    instance = described_class.new(reporter_options)
    instance.capacity.times do
      instance.queue << [:report, event]
    end
    instance.report event
    events = instrumenter.events_by_name("event_discarded.flipper")
    expect(events.size).to be(1)
  end

  it 'retries requests that error up to configured limit' do
    retry_strategy = Flipper::RetryStrategy.new(limit: 5, instrumenter: instrumenter, sleep: false)
    reporter_options = {
      client: client,
      instrumenter: instrumenter,
      retry_strategy: retry_strategy,
    }
    instance = described_class.new(reporter_options)

    exception = StandardError.new
    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .to_raise(exception)
    instance.report(event)
    instance.shutdown

    events = instrumenter.events_by_name("exception.flipper")
    expect(events.size).to be(retry_strategy.limit)
  end

  it 'retries 5xx response statuses up to configured limit' do
    instrumenter.reset

    retry_strategy = Flipper::RetryStrategy.new(limit: 5, instrumenter: instrumenter, sleep: false)
    reporter_options = {
      client: client,
      instrumenter: instrumenter,
      retry_strategy: retry_strategy,
    }
    instance = described_class.new(reporter_options)

    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .to_return(status: 500)

    instance.report(event)
    instance.shutdown

    events = instrumenter.events_by_name("exception.flipper")
    expect(events.size).to be(retry_strategy.limit)
  end

  it 'flushes at exit' do
    begin
      server = TestServer.new
      client = configuration.client(url: "http://localhost:#{server.port}")
      reporter_options[:client] = client
      reporter_options[:shutdown_automatically] = true
      reporter = described_class.new(reporter_options)

      pid = fork { reporter.report(event) }
      Process.waitpid pid, 0

      expect(server.event_receiver.size).to be(1)

      event_posts = server.access_lines.select { |line| line =~ %r{POST /events} }
      expect(event_posts.size).to be(1)
    ensure
      server.shutdown
    end
  end
end
