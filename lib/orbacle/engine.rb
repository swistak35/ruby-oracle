# frozen_string_literal: true

module Orbacle
  class Engine
    def initialize(logger)
      @logger = logger
    end

    attr_reader :stats_recorder

    def index(project_root)
      @stats_recorder = Indexer::StatsRecorder.new
      service = Indexer.new(logger, stats_recorder)
      @state, @graph, @worklist = service.(project_root: project_root)
    end

    def get_type_information(filepath, searched_position)
      relevant_nodes = @graph
        .vertices
        .select {|n| n.location && n.location.uri.eql?(filepath) && n.location.position_range.include_position?(searched_position) }
        .sort_by {|n| n.location.span }

      pretty_print_type(@state.type_of(relevant_nodes.at(0)))
    end

    def locations_for_definition_under_position(file_path, file_content, position)
      result = find_definition_under_position(file_content, position.line, position.character)
      case result
      when FindDefinitionUnderPosition::ConstantResult
        constants = @state.solve_reference2(result.const_ref)
        definitions_locations(constants)
      when FindDefinitionUnderPosition::MessageResult
        caller_type = get_type_of_caller_from_message_send(file_path, result.position_range)
        methods_definitions = get_methods_definitions_for_type(caller_type, result.name)
        methods_definitions = @state.get_methods(result.name) if methods_definitions.empty?
        definitions_locations(methods_definitions)
      when FindDefinitionUnderPosition::SuperResult
        method_surrounding_super = @state.find_method_including_position(file_path, result.keyword_position_range.start)
        return [] if method_surrounding_super.nil?
        super_method = @state.find_super_method(method_surrounding_super.id)
        return definitions_locations(@state.get_methods(method_surrounding_super.name) - [method_surrounding_super]) if super_method.nil?
        definitions_locations([super_method])
      end
    end

    def completions_for_call_under_position(file_content, position)
      result = FindCallUnderPosition.new(RubyParser.new).process_file(file_content, position)
      case result
      when FindCallUnderPosition::SelfResult
        filtered_methods_from_class_name(result.nesting.to_scope.to_const_name.to_string, result.message_name)
      when FindCallUnderPosition::IvarResult
        ivar_node = @graph.get_ivar_definition_node(result.nesting.to_scope, result.ivar_name)
        ivar_type = @state.type_of(ivar_node)
        methods = []
        ivar_type.each_possible_type do |type|
          methods.concat(filtered_methods_from_class_name(type.name, result.message_name))
        end
        methods
      else
        []
      end
    end

    private
    def definitions_locations(collection)
      collection.map(&:location).compact
    end

    def get_type_of_caller_from_message_send(file_path, position_range)
      message_send = @worklist
        .message_sends
        .find {|ms| ms.location && ms.location.uri.eql?(file_path) && ms.location.position_range.include_position?(position_range.start) }
      @state.type_of(message_send.send_obj)
    end

    def get_methods_definitions_for_type(type, method_name)
      case type
      when NominalType
        @state.get_deep_instance_methods_from_class_name(type.name, method_name)
      when ClassType
        @state.get_deep_class_methods_from_class_name(type.name, method_name)
      when UnionType
        type.types_set.flat_map {|t| get_methods_definitions_for_type(t, method_name) }
      else
        []
      end
    end

    private
    attr_reader :logger

    def find_definition_under_position(content, line, character)
      FindDefinitionUnderPosition.new(RubyParser.new).process_file(content, Position.new(line, character))
    end

    def pretty_print_type(type)
      TypePrettyPrinter.new.(type)
    end

    def filtered_methods_from_class_name(class_name, message_name)
      all_methods = @state.get_all_instance_methods_from_class_name(class_name)
      starting_with = all_methods.select do |metod|
        metod.name.to_s.start_with?(message_name.to_s)
      end
      starting_with.map(&:name).map(&:to_s)
    end
  end
end
