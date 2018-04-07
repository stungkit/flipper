require 'helper'
require 'flipper/retry_strategy'
require 'flipper/instrumenters/memory'

RSpec.describe Flipper::RetryStrategy do
  it 'defaults limit' do
    expect(subject.limit).to be(2_000)
  end

  it 'defaults sleep' do
    expect(subject.sleep).to be(true)
  end

  it 'defaults base' do
    expect(subject.base).to be(0.5)
  end

  it 'defaults max_delay' do
    expect(subject.max_delay).to be(60.0)
  end

  it 'defaults raise_at_limit' do
    expect(subject.raise_at_limit).to be(false)
  end

  it 'defaults instrumenter' do
    expect(subject.instrumenter).to be(Flipper::Instrumenters::Noop)
  end

  describe '#call' do
    let(:raiser) { -> { raise } }
    let(:succeeder) { -> { :return_value } }

    it 'raises if no block provided' do
      expect { subject.call }.to raise_error(ArgumentError)
    end

    it 'retries up to limit and instruments errors' do
      instrumenter = Flipper::Instrumenters::Memory.new
      retry_strategy = described_class.new(sleep: false, instrumenter: instrumenter)
      retry_strategy.call { raiser.call }

      events = instrumenter.events_by_name("exception.flipper")
      expect(events.size).to be(retry_strategy.limit)
    end

    it 'returns block value if succeeds prior to limit' do
      instrumenter = Flipper::Instrumenters::Memory.new
      retry_strategy = described_class.new(sleep: false, instrumenter: instrumenter)
      results = []
      (retry_strategy.limit - 1).times { results << raiser }
      results << succeeder

      call_result = retry_strategy.call { results.shift.call }
      expect(call_result).to be(:return_value)

      events = instrumenter.events_by_name("exception.flipper")
      expect(events.size).to be(retry_strategy.limit - 1)
    end

    it 'raises if limit hit and raise_at_limit is true' do
      instrumenter = Flipper::Instrumenters::Memory.new
      retry_strategy_options = {
        sleep: false,
        raise_at_limit: true,
        instrumenter: instrumenter,
      }

      retry_strategy = described_class.new(retry_strategy_options)
      expect { retry_strategy.call { raiser.call } }.to raise_error(RuntimeError)

      events = instrumenter.events_by_name("exception.flipper")
      expect(events.size).to be(retry_strategy.limit)
    end
  end
end
