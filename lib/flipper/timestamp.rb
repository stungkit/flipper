module Flipper
  module Timestamp
    module_function

    def generate(now = Time.now)
      (now.to_f * 1_000).floor
    end
  end
end
