require 'parser/current'
require 'orbacle/nesting_container'

class Orbacle::ParseFileMethods < Parser::AST::Processor
  def initialize
  end

  def process_file(file)
    ast = Parser::CurrentRuby.parse(file)

    reset_file!

    process(ast)

    return {
      methods: @methods,
      constants: @constants,
    }
  end

  def on_module(ast)
    ast_name, _ = ast.children
    prename, module_name = @current_nesting.get_nesting(ast_name)

    @constants << [
      scope_from_nesting_and_prename(@current_nesting.get_current_nesting, prename),
      module_name,
      :mod,
      { line: ast_name.loc.line },
    ]

    @current_nesting.increase_nesting_mod(ast_name)

    super(ast)

    @current_nesting.decrease_nesting
  end

  def on_class(ast)
    ast_name, _ = ast.children
    prename, klass_name = @current_nesting.get_nesting(ast_name)

    @constants << [
      scope_from_nesting_and_prename(@current_nesting.get_current_nesting, prename),
      klass_name,
      :klass,
      { line: ast_name.loc.line },
    ]

    @current_nesting.increase_nesting_class(ast_name)

    super(ast)

    @current_nesting.decrease_nesting
  end

  def on_def(ast)
    method_name, _ = ast.children

    @methods << [ nesting_to_scope(@current_nesting.get_current_nesting), method_name.to_s ]

    super(ast)
  end

  def on_casgn(ast)
    const_prename, const_name, _ = ast.children

    @constants << [
      scope_from_nesting_and_prename(@current_nesting.get_current_nesting, @current_nesting.prename(const_prename)),
      const_name.to_s,
      :other,
      { line: ast.loc.line }
    ]

    super(ast)
  end

  private

  def reset_file!
    @current_nesting = Orbacle::NestingContainer.new
    @methods = []
    @constants = []
  end

  def nesting_to_scope(nesting)
    return nil if nesting.empty?

    nesting.map do |_type, pre, name|
      pre + [name]
    end.flatten.join("::")
  end

  def scope_from_nesting_and_prename(nesting, prename)
    scope_from_nesting = nesting_to_scope(nesting)

    if prename[0] == ""
      result = prename[1..-1].compact.join("::")
    else
      result = ([scope_from_nesting] + prename).compact.join("::")
    end
    result.empty? ? nil : result
  end
end