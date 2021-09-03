module Flipper
  module Rules
    # Flipper::Rule.build do
    #   any [
    #     property("admin").eq(true),
    #     all [
    #       property("age").gte(21),
    #       property("plan").eq("paid"),
    #       condition("buyer").in(property("roles"))
    #     ]
    #   ]
    # end
    class Builder
      def all(rules)
        All.new rules
      end

      def any(rules)
        Any.new rules
      end

      def property(name)
        ConditionBuilder.new(Property.new(name))
      end

      def condition(value)
        ConditionBuilder.new(value)
      end
    end

    class ConditionBuilder < Struct.new(:left)
      # TODO proxy to :left

      Condition::OPERATIONS.keys.each do |operator|
        define_method(operator) do |right|
          Condition.new(left, operator, right)
        end
      end
    end
  end
end
