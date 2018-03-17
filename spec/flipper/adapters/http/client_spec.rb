require 'helper'
require 'flipper/adapters/http/client'

RSpec.describe Flipper::Adapters::Http::Client do
  describe '#url_for' do
    it 'works for url and path' do
      expect(described_class.url_for("https://foo.com", "bar"))
        .to eq("https://foo.com/bar")

      expect(described_class.url_for("https://foo.com/", "bar"))
        .to eq("https://foo.com/bar")

      expect(described_class.url_for("https://foo.com", "/bar"))
        .to eq("https://foo.com/bar")

      expect(described_class.url_for("https://foo.com/", "/bar"))
        .to eq("https://foo.com/bar")
    end

    it 'works for url with path and more path' do
      expect(described_class.url_for("https://foo.com/adapter", "bar"))
        .to eq("https://foo.com/adapter/bar")

      expect(described_class.url_for("https://foo.com/adapter/", "bar"))
        .to eq("https://foo.com/adapter/bar")

      expect(described_class.url_for("https://foo.com/adapter", "/bar"))
        .to eq("https://foo.com/adapter/bar")

      expect(described_class.url_for("https://foo.com/adapter/", "/bar"))
        .to eq("https://foo.com/adapter/bar")
    end

    it 'works for url with path and query string and more path' do
      expect(described_class.url_for("https://foo.com/adapter?baz=1", "bar"))
        .to eq("https://foo.com/adapter/bar?baz=1")
    end

    it 'works for url with path and query string and more path with query string' do
      expect(described_class.url_for("https://foo.com/adapter?baz=1", "bar?wick=0"))
        .to eq("https://foo.com/adapter/bar?baz=1&wick=0")

      expect(described_class.url_for("https://foo.com/adapter?baz=1", "/bar?wick=0"))
        .to eq("https://foo.com/adapter/bar?baz=1&wick=0")

      expect(described_class.url_for("https://foo.com/adapter?baz=1", "/bar?"))
        .to eq("https://foo.com/adapter/bar?baz=1&")

      expect(described_class.url_for("https://foo.com/adapter?baz=1&a=b&", "/bar?c=d&e=f"))
        .to eq("https://foo.com/adapter/bar?baz=1&a=b&c=d&e=f")
    end

    it 'supports http scheme' do
      expect(described_class.url_for("http://foo.com", "bar"))
        .to eq("http://foo.com/bar")
    end

    it 'supports https scheme' do
      expect(described_class.url_for("https://foo.com", "bar"))
        .to eq("https://foo.com/bar")
    end

    it 'raises ArgumentError if url is nil' do
      expect { described_class.url_for(nil, "events") }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError for invalid scheme' do
      expect { described_class.url_for("ftp://foo", "events") }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError if path is nil' do
      expect { described_class.url_for("https://foo.com", nil) }.to raise_error(ArgumentError)
    end
  end
end
