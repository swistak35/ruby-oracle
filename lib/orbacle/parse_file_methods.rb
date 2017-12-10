require 'parser/current'
require 'orbacle/nesting_container'

module Orbacle
  class ParseFileMethods < Parser::AST::Processor
    class Klasslike
      def self.build_module(scope:, name:)
        new(
          scope: scope,
          name: name,
          type: :module,
          inheritance: nil,
          nesting: nil)
      end

      def self.build_klass(scope:, name:, inheritance:, nesting:)
        new(
          scope: scope,
          name: name,
          type: :klass,
          inheritance: inheritance,
          nesting: nesting)
      end

      def initialize(scope:, name:, type:, inheritance:, nesting:)
        @scope = scope
        @name = name
        @type = type
        @inheritance = inheritance
        @nesting = nesting
      end

      attr_reader :scope, :name, :type, :inheritance, :nesting

      def ==(other)
        @scope == other.scope &&
          @name == other.name &&
          @type == other.type &&
          @inheritance == other.inheritance &&
          @nesting == other.nesting
      end
    end

    def process_file(file)
      ast = Parser::CurrentRuby.parse(file)

      reset_file!

      process(ast)

      {
        methods: @methods,
        constants: @constants,
        klasslikes: @klasslikes,
      }
    end

    def on_module(ast)
      ast_name, _ = ast.children
      prename, module_name = AstUtils.get_nesting(ast_name)

      @constants << [
        @current_nesting.scope_from_nesting_and_prename(prename),
        module_name,
        :mod,
        { line: ast_name.loc.line },
      ]

      @klasslikes << Klasslike.build_module(
        scope: @current_nesting.scope_from_nesting_and_prename(prename),
        name: module_name.to_s)

      @current_nesting.increase_nesting_mod(ast_name)

      super(ast)

      @current_nesting.decrease_nesting
    end

    def on_class(ast)
      ast_name, parent_klass_name_ast, _ = ast.children
      prename, klass_name = AstUtils.get_nesting(ast_name)

      @constants << [
        @current_nesting.scope_from_nesting_and_prename(prename),
        klass_name,
        :klass,
        { line: ast_name.loc.line },
      ]

      @klasslikes << Klasslike.build_klass(
        scope: @current_nesting.scope_from_nesting_and_prename(prename),
        name: klass_name.to_s,
        inheritance: parent_klass_name_ast.nil? ? nil : AstUtils.get_nesting(parent_klass_name_ast).flatten.join("::"),
        nesting: @current_nesting.get_output_nesting)

      @current_nesting.increase_nesting_class(ast_name)

      super(ast)

      @current_nesting.decrease_nesting
    end

    def on_sclass(ast)
      @current_nesting.make_nesting_selfed

      super(ast)

      @current_nesting.make_nesting_not_selfed
    end

    def on_def(ast)
      method_name, _ = ast.children

      @methods << [
        @current_nesting.nesting_to_scope,
        method_name.to_s,
        { line: ast.loc.line, target: @current_nesting.is_selfed? ? :self : :instance }
      ]
    end

    def on_defs(ast)
      method_receiver, method_name, _ = ast.children

      @methods << [
        @current_nesting.nesting_to_scope,
        method_name.to_s,
        { line: ast.loc.line, target: :self },
      ]
    end

    def on_casgn(ast)
      const_prename, const_name, expr = ast.children

      @constants << [
        @current_nesting.scope_from_nesting_and_prename(AstUtils.prename(const_prename)),
        const_name.to_s,
        :other,
        { line: ast.loc.line }
      ]

      if expr_is_class_definition?(expr)
        parent_klass_name_ast = expr.children[2]
        @klasslikes << Klasslike.build_klass(
          scope: @current_nesting.scope_from_nesting_and_prename(AstUtils.prename(const_prename)),
          name: const_name.to_s,
          inheritance: parent_klass_name_ast.nil? ? nil : AstUtils.get_nesting(parent_klass_name_ast).flatten.join("::"),
          nesting: @current_nesting.get_output_nesting)
      elsif expr_is_module_definition?(expr)
        @klasslikes << Klasslike.build_module(
          scope: @current_nesting.scope_from_nesting_and_prename(AstUtils.prename(const_prename)),
          name: const_name.to_s)
      end
    end

    private

    def reset_file!
      @current_nesting = NestingContainer.new
      @methods = []
      @constants = []
      @klasslikes = []
    end

    def expr_is_class_definition?(expr)
      expr.type == :send &&
        expr.children[0] == Parser::AST::Node.new(:const, [nil, :Class]) &&
        expr.children[1] == :new
    end

    def expr_is_module_definition?(expr)
      expr.type == :send &&
        expr.children[0] == Parser::AST::Node.new(:const, [nil, :Module]) &&
        expr.children[1] == :new
    end
  end
end
