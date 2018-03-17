require "flipper/timestamp"

module Flipper
  class Event
    attr_reader :type, :timestamp, :dimensions

    def self.from_hash(hash)
      attributes = {
        type: hash.fetch("type"),
        timestamp: hash.fetch("timestamp"),
        dimensions: hash.fetch("dimensions"),
      }
      new attributes
    end

    def initialize(attributes = {})
      @type = attributes.fetch(:type)
      @dimensions = attributes.fetch(:dimensions) { {} }
      @timestamp = attributes.fetch(:timestamp) { Flipper::Timestamp.generate }
    end

    def as_json
      @as_json ||= {
        type: type,
        timestamp: timestamp,
        dimensions: dimensions,
      }
    end
  end
end
