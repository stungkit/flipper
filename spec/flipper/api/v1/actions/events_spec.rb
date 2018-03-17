require 'helper'
require 'flipper/api/v1/actions/events'
require 'flipper/event_receivers/memory'

RSpec.describe Flipper::Api::V1::Actions::Events do
  let(:event_receiver) { Flipper::EventReceivers::Memory.new }
  let(:app) { build_api(flipper, event_receiver: event_receiver) }

  describe 'post' do
    context 'valid' do
      it 'responds with 201' do
        now = Flipper::Timestamp.generate
        client_timestamp = now - 100
        timestamp = now - 1000
        env = {
          "CONTENT_TYPE" => "application/json",
          "HTTP_USER_AGENT" => "Flipper",
          "HTTP_FLIPPER_PID" => "123",
          "HTTP_FLIPPER_THREAD" => "70147860499320",
          "HTTP_FLIPPER_HOSTNAME" => "foobar.com",
          "HTTP_FLIPPER_VERSION" => Flipper::VERSION,
          "HTTP_FLIPPER_PLATFORM" => "ruby",
          "HTTP_FLIPPER_PLATFORM_VERSION" => "2.3.3",
          "HTTP_FLIPPER_TIMESTAMP" => client_timestamp.to_s,
        }
        dimensions = {
          "feature" => "foo",
          "flipper_id" => "User;23",
          "result" => "true",
        }
        attributes = {
          events: [
            { type: 'enabled', dimensions: dimensions, timestamp: timestamp },
          ],
        }
        body = JSON.generate(attributes)
        post '/events', body, env

        expect(last_response.status).to be(201)

        expected_response = {}
        expect(json_response).to eq(expected_response)
        expect(event_receiver.size).to be(1)

        batch = event_receiver.first
        expect(batch).not_to be(nil)
        expect(batch.ip).to eq("127.0.0.1")
        expect(batch.pid).to eq("123")
        expect(batch.thread).to eq("70147860499320")
        expect(batch.hostname).to eq("foobar.com")
        expect(batch.user_agent).to eq("Flipper")
        expect(batch.version).to eq(Flipper::VERSION)
        expect(batch.platform).to eq("ruby")
        expect(batch.platform_version).to eq("2.3.3")
        expect(batch.client_timestamp).to eq(client_timestamp.to_s)
        expect(batch.timestamp >= now).to be(true)
        expect(batch.events.size).to be(1)

        event = batch.events.first
        expect(event.type).to eq("enabled")
        expect(event.dimensions).to eq(dimensions)
        expect(event.timestamp).to eq(timestamp)
      end
    end

    context 'invalid' do
      it 'responds with 422 and errors' do
        env = {
          "CONTENT_TYPE" => "application/json",
        }
        post "/events", "{}", env

        expect(last_response.status).to be(422)

        batch = event_receiver.first
        expect(batch).to be_nil
      end
    end
  end
end
