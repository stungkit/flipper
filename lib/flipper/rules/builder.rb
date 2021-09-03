module Flipper
  module Rules
    # Flipper::Rules.build do
    #   any do
    #     property("admin").eq(true)
    #     all do
    #       property("age").gte(21)
    #       property("plan").eq("paid")
    #       condition("buyer").in(property("roles"))
    #     end
    #   end
    # end
    class Builder
      attr_reader :rules

      def initialize
        @rules = []
      end

      def all(&block)
        builder = Builder.new
        instance_exec &block
        @rules << All.new(builder.rules)
      end

      def any(&block)
        builder = Builder.new
        instance_exec &block
        @rules << Any.new(builder.rules)
      end

      def property(name)
        ConditionBuilder.new(self, Property.new(name))
      end

      def condition(value)
        ConditionBuilder.new(self, value)
      end
    end

    class ConditionBuilder < Struct.new(:builder, :left)
      # TODO proxy to :left

      Condition::OPERATIONS.keys.each do |operator|
        define_method(operator) do |right|
          builder.rules << Condition.new(left, operator, right)
        end
      end
    end
  end
end
