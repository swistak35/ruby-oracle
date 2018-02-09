require 'spec_helper'

RSpec.describe Orbacle::ControlFlowGraph do
  def build_klass(scope: nil, name:, inheritance: nil, nesting: [])
    # Orbacle::ControlFlowGraph::GlobalTree::Klass.new(scope: scope, name: name, inheritance_name: inheritance, inheritance_nesting: nesting, line: line)
    [Orbacle::ControlFlowGraph::GlobalTree::Klass, scope, name, inheritance, nesting]
  end

  def build_module(scope: nil, name:)
    # Orbacle::ControlFlowGraph::GlobalTree::Mod.new(scope: scope, name: name, line: line)
    [Orbacle::ControlFlowGraph::GlobalTree::Mod, scope, name]
  end

  def build_constant(scope: nil, name:)
    [Orbacle::ControlFlowGraph::GlobalTree::Constant, scope, name]
  end

  specify do
    file = <<-END
    class Foo
      def bar
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Foo", "bar", { line: 2 }],
    ])
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo")
    ])
  end

  specify do
    file = <<-END
    class Foo
      def bar
      end

      def baz
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Foo", "bar", { line: 2 }],
      ["::Foo", "baz", { line: 5 }],
    ])
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo", scope: nil)
    ])
  end

  it do
    file = <<-END
    module Some
      class Foo
        def bar
        end

        def baz
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Some::Foo", "bar", { line: 3 }],
      ["::Some::Foo", "baz", { line: 6 }],
    ])
    expect(r[:constants]).to match_array([
      build_module(name: "Some"),
      build_klass(scope: "::Some", name: "Foo", nesting: ["Some"]),
    ])
  end

  it do
    file = <<-END
    module Some
      class Foo
        def oof
        end
      end

      class Bar
        def rab
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Some::Foo", "oof", { line: 3 }],
      ["::Some::Bar", "rab", { line: 8 }],
    ])
    expect(r[:constants]).to match_array([
      build_module(name: "Some"),
      build_klass(scope: "::Some", name: "Foo", nesting: ["Some"]),
      build_klass(scope: "::Some", name: "Bar", nesting: ["Some"]),
    ])
  end

  it do
    file = <<-END
    module Some
      module Foo
        class Bar
          def baz
          end
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Some::Foo::Bar", "baz", { line: 4 }],
    ])
    expect(r[:constants]).to match_array([
      build_module(name: "Some"),
      build_module(scope: "::Some", name: "Foo"),
      build_klass(scope: "::Some::Foo", name: "Bar", nesting: ["Some", "Foo"]),
    ])
  end

  it do
    file = <<-END
    module Some::Foo
      class Bar
        def baz
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Some::Foo::Bar", "baz", { line: 3 }],
    ])
    expect(r[:constants]).to match_array([
      build_module(scope: "::Some", name: "Foo"),
      build_klass(scope: "::Some::Foo", name: "Bar", nesting: ["Some::Foo"]),
    ])
  end

  it do
    file = <<-END
    module Some::Foo::Bar
      class Baz
        def xxx
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Some::Foo::Bar::Baz", "xxx", { line: 3 }],
    ])
    expect(r[:constants]).to match_array([
      build_module(scope: "::Some::Foo", name: "Bar"),
      build_klass(scope: "::Some::Foo::Bar", name: "Baz", nesting: ["Some::Foo::Bar"]),
    ])
  end

  it do
    file = <<-END
    module Some::Foo
      class Bar::Baz
        def xxx
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Some::Foo::Bar::Baz", "xxx", { line: 3 }],
    ])
    expect(r[:constants]).to match_array([
      build_module(scope: "::Some", name: "Foo"),
      build_klass(scope: "::Some::Foo::Bar", name: "Baz", nesting: ["Some::Foo"])
    ])
  end

  it do
    file = <<-END
    class Bar
      class ::Foo
        def xxx
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Foo", "xxx", { line: 3 }],
    ])
    expect(r[:constants]).to match_array([
      build_klass(name: "Bar"),
      build_klass(name: "Foo", nesting: ["Bar"])
    ])
  end

  it do
    file = <<-END
    class Bar
      module ::Foo
        def xxx
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Foo", "xxx", { line: 3 }],
    ])
    expect(r[:constants]).to match_array([
      build_klass(name: "Bar"),
      build_module(name: "Foo"),
    ])
  end

  it do
    file = <<-END
    def xxx
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      [nil, "xxx", { line: 1 }],
    ])
    expect(r[:constants]).to be_empty
  end

  specify do
    file = <<-END
    class Foo
      Bar = 32

      def bar
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Foo", "bar", { line: 4 }],
    ])
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo"),
      build_constant(name: "Bar", scope: "::Foo")
    ])
  end

  specify do
    file = <<-END
    class Foo
      Ban::Baz::Bar = 32
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([])
    expect(r[:constants]).to match_array([
      build_constant(name: "Bar", scope: "::Foo::Ban::Baz"),
      build_klass(name: "Foo"),
    ])
  end

  specify do
    file = <<-END
    class Foo
      ::Bar = 32
    end
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_constant(name: "Bar", scope: nil),
      build_klass(name: "Foo"),
    ])
  end

  specify do
    file = <<-END
    class Foo
      ::Baz::Bar = 32
    end
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_constant(name: "Bar", scope: "::Baz"),
      build_klass(name: "Foo"),
    ])
  end

  specify do
    file = <<-END
    class Foo
      ::Baz::Bam::Bar = 32
    end
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_constant(name: "Bar", scope: "::Baz::Bam"),
      build_klass(name: "Foo"),
    ])
  end

  it do
    file = <<-END
    module Some
      module Foo
        def oof
        end
      end

      module Bar
        def rab
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["::Some::Foo", "oof", { line: 3 }],
      ["::Some::Bar", "rab", { line: 8 }],
    ])
    expect(r[:constants]).to match_array([
      build_module(name: "Some"),
      build_module(scope: "::Some", name: "Foo"),
      build_module(scope: "::Some", name: "Bar"),
    ])
  end

  specify do
    file = <<-END
    class Foo < Bar
    end
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo", inheritance: "Bar")
    ])
  end

  specify do
    file = <<-END
    class Foo < Bar::Baz
    end
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo", inheritance: "Bar::Baz")
    ])
  end

  specify do
    file = <<-END
    class Foo < ::Bar::Baz
    end
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo", inheritance: "::Bar::Baz")
    ])
  end

  specify do
    file = <<-END
    module Some
      class Foo < Bar
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_module(name: "Some"),
      build_klass(scope: "::Some", name: "Foo", inheritance: "Bar", nesting: ["Some"]),
    ])
  end

  specify do
    file = <<-END
    Foo = Class.new(Bar)
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo", inheritance: "Bar")
    ])
  end

  specify do
    file = <<-END
    Foo = Class.new
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_klass(name: "Foo")
    ])
  end

  specify do
    file = <<-END
    Foo = Module.new
    END

    r = parse_file_methods.(file)
    expect(r[:constants]).to match_array([
      build_module(name: "Foo")
    ])
  end

  specify do
    file = <<-END
    class Foo
      def self.bar
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["Metaklass(::Foo)", "bar", { line: 2 }],
    ])
  end

  specify do
    file = <<-END
    class Foo
      class << self
        def foo
        end
      end
    end
    END

    r = parse_file_methods.(file)
    expect(r[:methods]).to eq([
      ["Metaklass(::Foo)", "foo", { line: 3 }],
    ])
  end

  def parse_file_methods
    ->(file) {
      service = Orbacle::ControlFlowGraph.new
      result = service.process_file(file)
      {
        methods: result.methods.map {|m| m[0..2] },
        constants: result.constants.map do |c|
          if c.is_a?(Orbacle::ControlFlowGraph::GlobalTree::Klass)
            [c.class, c.scope, c.name, c.inheritance_name, c.inheritance_nesting]
          else
            [c.class, c.scope, c.name]
          end
        end
      }
    }
  end
end
