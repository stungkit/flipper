require 'helper'
require 'flipper/retry_strategy'
require 'flipper/instrumenters/memory'

RSpec.describe Flipper::RetryStrategy do
  it 'defaults limit' do
    expect(subject.limit).to be(10)
  end

  it 'defaults sleep' do
    expect(subject.sleep).to be(true)
  end

  it 'defaults base' do
    expect(subject.base).to be(0.5)
  end

  it 'defaults max_delay' do
    expect(subject.max_delay).to be(2.0)
  end

  it 'defaults instrumenter' do
    expect(subject.instrumenter).to be(Flipper::Instrumenters::Noop)
  end

  it 'instruments retries' do
    instrumenter = Flipper::Instrumenters::Memory.new
    instance = described_class.new(instrumenter: instrumenter, sleep: false)

    begin
      instance.call { raise }
      flunk # should not get here
    rescue
      events = instrumenter.events_by_name("retry_strategy_exception.flipper")
      expect(events.size).to be(instance.limit)
    end
  end

  describe '#call' do
    let(:raiser) { -> { raise } }
    let(:succeeder) { -> { :return_value } }

    it 'raises if no block provided' do
      expect { subject.call }.to raise_error(ArgumentError)
    end

    it 'retries up to limit then raises' do
      retry_strategy = described_class.new(sleep: false)
      expect { retry_strategy.call { raiser.call } }.to raise_error(RuntimeError)
    end

    it 'does not raise if succeeds prior to limit' do
      retry_strategy = described_class.new(sleep: false)
      results = []
      (retry_strategy.limit - 1).times { results << raiser }
      results << succeeder
      call_result = retry_strategy.call { results.shift.call }
      expect(call_result).to be(:return_value)
    end
  end
end
