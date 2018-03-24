require 'helper'
require 'flipper/event'
require 'flipper/cloud'
require 'flipper/cloud/configuration'
require 'flipper/cloud/producer'
require 'flipper/instrumenters/memory'

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

  let(:client) do
    client_options = {
      token: "asdf",
      url: "https://www.featureflipper.com/adapter",
    }
    Flipper::Adapters::Http::Client.new(client_options)
  end

  subject do
    producer_options = {
      client: client,
      capacity: 10,
      batch_size: 5,
      flush_interval: 0.1,
      retry_strategy: Flipper::RetryStrategy.new(sleep: false),
      instrumenter: instrumenter,
    }
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

  it 'instruments producer response errors' do
    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .to_return(status: 500)
    subject.produce(event)
    subject.shutdown

    submission_event = instrumenter.event_by_name("producer_response_error.flipper")
    expect(submission_event).not_to be_nil
    expect(submission_event.payload[:response]).to be_instance_of(Net::HTTPInternalServerError)
  end

  it 'instruments producer exceptions' do
    exception = StandardError.new
    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .to_raise(exception)
    subject.produce(event)
    subject.shutdown

    exception_event = instrumenter.event_by_name("producer_exception.flipper")
    expect(exception_event.payload.fetch(:exception)).to be(exception)
  end

  it 'retries submission exceptions up to configured limit' do
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

    events = instrumenter.events_by_name("retry_strategy_exception.flipper")
    expect(events.size).to be(retry_strategy.limit)

    events = instrumenter.events_by_name("producer_exception.flipper")
    expect(events.size).to be(1)
  end

  it 'retries 5xx response statuses up to configured limit and instruments error' do
    (500..599).each do |status|
      instrumenter.reset

      retry_strategy = Flipper::RetryStrategy.new(instrumenter: instrumenter, sleep: false)
      producer_options = {
        client: client,
        instrumenter: instrumenter,
        retry_strategy: retry_strategy,
      }
      instance = described_class.new(producer_options)

      stub_request(:post, "https://www.featureflipper.com/adapter/events")
        .to_return(status: status)

      instance.produce(event)
      instance.shutdown

      events = instrumenter.events_by_name("producer_response_error.flipper")
      expect(events.size).to be(retry_strategy.limit)
    end
  end
end
