require "helper"
require "flipper/cloud/request"
require "flipper/cloud/configuration"
require "flipper/instrumenters/memory"

RSpec.describe Flipper::Cloud::Request do
  let(:instrumenter) { Flipper::Instrumenters::Memory.new }

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

  let(:request_options) do
    {
      limit: 5,
      client: client,
      instrumenter: instrumenter,
    }
  end

  describe '#<<' do
    context 'when not at limit' do
      let(:request) { described_class.new(request_options) }

      before do
        @stub = stub_request(:post, "https://www.featureflipper.com/adapter/events")
                .to_return(status: 200, body: "{}")

        @events = request << event
      end

      it 'adds event to events array and returns it' do
        expect(@events.size).to be(1)
      end

      it 'does not perform request' do
        expect(@stub).not_to have_been_requested
      end
    end

    context 'when at limit' do
      let(:request) { described_class.new(request_options) }

      before do
        @stub = stub_request(:post, "https://www.featureflipper.com/adapter/events")
                .to_return(status: 200, body: "{}")

        request.limit.times { @events = request << event }
      end

      it 'performs request' do
        expect(@stub).to have_been_requested
      end

      it 'resets events array and returns it' do
        expect(@events.size).to be(0)
      end
    end
  end

  describe '#perform' do
    it 'does nothing if empty' do
      stub = stub_request(:post, "https://www.featureflipper.com/adapter/events")
             .to_return(status: 200, body: "{}")

      request = described_class.new(request_options)
      request.perform

      expect(stub).not_to have_been_requested
    end

    it 'uses the same request id across retries' do
      allow(SecureRandom).to receive(:hex).with(16).and_return("1", "2")

      stub = stub_request(:post, "https://www.featureflipper.com/adapter/events")
             .with(headers: { "Flipper-Request-Id" => "1" })
             .to_return(status: 500, body: "{}")

      retry_strategy_options = {
        limit: 5,
        sleep: false,
        instrumenter: instrumenter,
      }
      request_options[:retry_strategy] = Flipper::RetryStrategy.new(retry_strategy_options)

      request = described_class.new(request_options)
      request << event
      request.perform

      expect(stub).to have_been_requested.times(5)
    end

    it 'uses retry strategy' do
      stub = stub_request(:post, "https://www.featureflipper.com/adapter/events")
             .to_return(status: 500, body: "{}")

      retry_strategy_options = {
        limit: 5,
        sleep: false,
        instrumenter: instrumenter,
      }
      request_options[:retry_strategy] = Flipper::RetryStrategy.new(retry_strategy_options)

      request = described_class.new(request_options)
      request << event
      request.perform

      expect(stub).to have_been_requested.times(5)

      events = instrumenter.events_by_name("exception.flipper")
      expect(events.size).to be(5)
    end

    it 'instruments exceptions' do
      exception = StandardError.new
      expect(JSON).to receive(:generate).and_raise(exception)

      request = described_class.new(request_options)
      request << event
      request.perform

      events = instrumenter.events_by_name("exception.flipper")
      expect(events.size).to be(1)

      event = events.first
      expect(event.payload.fetch(:context)).to eq("Flipper::Cloud::Request#perform")

      # resets events since the assumption is that any non rescued errors will
      # continue to happen, better to discard and movee on
      expect(request.events.size).to be(0)
    end

    it 'resets upon completion' do
      stub = stub_request(:post, "https://www.featureflipper.com/adapter/events")
             .to_return(status: 200, body: "{}")

      request = described_class.new(request_options)
      request << event
      request.perform

      expect(stub).to have_been_requested
      expect(request.events.size).to be(0)
    end
  end
end
