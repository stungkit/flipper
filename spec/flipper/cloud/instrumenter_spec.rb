require 'helper'
require 'flipper/adapters/http/client'
require 'flipper/instrumenters/memory'
require 'flipper/cloud/producer'
require 'flipper/cloud/instrumenter'

RSpec.describe Flipper::Cloud::Instrumenter do
  let(:client) do
    Flipper::Adapters::Http::Client.new(url: "https://www.featureflipper.com/adapter")
  end
  let(:producer) { Flipper::Cloud::Producer.new(client: client) }
  let(:instrumenter) { Flipper::Instrumenters::Memory.new }

  subject { described_class.new(instrumenter: instrumenter, producer: producer) }

  it 'produces event for cloud if feature enabled operation' do
    stub_request(:post, "https://www.featureflipper.com/adapter/events")
      .to_return(status: 201)

    payload = {
      operation: :enabled?,
      feature_name: :foo,
      result: true,
    }
    subject.instrument(Flipper::Feature::InstrumentationName, payload)
    producer.shutdown
    expect(producer.queue.size).to be(0)
  end

  it 'instruments producer errors' do
    payload = {
      operation: :enabled?,
      feature_name: :foo,
      result: true,
    }
    exception = StandardError.new

    expect(producer).to receive(:produce).and_raise(exception)
    expect { subject.instrument(Flipper::Feature::InstrumentationName, payload) }
      .not_to raise_error

    producer_exception_events = instrumenter.events.select do |event|
      event.name == "producer_exception.flipper"
    end

    expect(producer_exception_events.size).to be(1)
    payload = producer_exception_events.first.payload
    expect(payload.fetch(:exception)).to be(exception)
  end

  describe '#instrument with block' do
    before do
      @yielded = 0
      @result = subject.instrument(:foo, bar: "baz") do
        @yielded += 1
        :foo_result
      end
    end

    it 'sends instrument to wrapped instrumenter' do
      expect(instrumenter.events.size).to be(1)
      event = instrumenter.events.first
      expect(event.name).to eq(:foo)
      expect(event.payload).to eq(bar: "baz")
    end

    it 'returns result of wrapped instrumenter instrument method call' do
      expect(@result).to eq :foo_result
    end

    it 'only yields block once' do
      expect(@yielded).to eq 1
    end
  end

  describe '#instrument without block' do
    before do
      @result = subject.instrument(:foo, bar: "baz")
    end

    it 'sends instrument to wrapped instrumenter' do
      expect(instrumenter.events.size).to be(1)
      event = instrumenter.events.first
      expect(event.name).to eq(:foo)
      expect(event.payload).to eq(bar: "baz")
    end
  end
end
