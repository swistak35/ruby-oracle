require 'rgl/adjacency'

module Orbacle
  module DataFlowGraph
    class Graph
      def initialize
        @graph = RGL::DirectedAdjacencyGraph.new

        @global_variables = {}
        @constants = {}
        @main_ivariables = {}
      end

      attr_reader :constants

      def add_vertex(node)
        @graph.add_vertex(node)
        node
      end

      def add_edges(nodes_source, nodes_target)
        Array(nodes_source).each do |source|
          Array(nodes_target).each do |target|
            @graph.add_edge(source, target)
          end
        end
      end

      def add_edge(x, y)
        @graph.add_edge(x, y)
      end

      def edges
        @graph.edges
      end

      def vertices
        @graph.vertices
      end

      def adjacent_vertices(v)
        @graph.adjacent_vertices(v)
      end

      def reverse
        @graph.reverse
      end

      def has_edge?(x, y)
        @graph.has_edge?(x, y)
      end

      def get_gvar_definition_node(gvar_name)
        if !global_variables[gvar_name]
          global_variables[gvar_name] = add_vertex(Node.new(:gvar_definition))
        end

        return global_variables[gvar_name]
      end

      def get_main_ivar_definition_node(ivar_name)
        if !main_ivariables[ivar_name]
          main_ivariables[ivar_name] = add_vertex(Node.new(:ivar_definition))
        end

        return main_ivariables[ivar_name]
      end

      def get_constant_definition_node(const_name)
        if !constants[const_name]
          constants[const_name] = add_vertex(Node.new(:const_definition))
        end

        return constants[const_name]
      end

      private
      attr_reader :global_variables, :main_ivariables
    end
  end
end
