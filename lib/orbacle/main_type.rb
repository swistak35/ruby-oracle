module Orbacle
  class MainType
    def each_possible_type
    end

    def pretty
      "main"
    end

    def ==(other)
      self.class == other.class
    end

    def hash
      [
        self.class,
      ].hash ^ BIG_VALUE
    end
    alias eql? ==

    def bottom?
      false
    end
  end
end
