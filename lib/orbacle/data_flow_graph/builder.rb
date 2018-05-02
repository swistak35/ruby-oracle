require 'parser/current'
require 'orbacle/nesting'

module Orbacle
  module DataFlowGraph
    class Builder
      class Result
        def initialize(node, context, data = {})
          @node = node
          @context = context.freeze
          @data = data.freeze
        end
        attr_reader :node, :context, :data
      end

      class Context
        AnalyzedKlass = Struct.new(:klass, :method_visibility)

        def initialize(filepath, selfie, nesting, analyzed_klass, analyzed_method, lenv)
          @filepath = filepath.freeze
          @selfie = selfie.freeze
          @nesting = nesting.freeze
          @analyzed_klass = analyzed_klass.freeze
          @analyzed_method = analyzed_method
          @lenv = lenv.freeze
        end

        attr_reader :filepath, :selfie, :nesting, :analyzed_klass, :analyzed_method, :lenv

        def with_selfie(new_selfie)
          self.class.new(filepath, new_selfie, nesting, analyzed_klass, analyzed_method, lenv)
        end

        def with_nesting(new_nesting)
          self.class.new(filepath, selfie, new_nesting, analyzed_klass, analyzed_method, lenv)
        end

        def scope
          nesting.to_scope
        end

        def with_analyzed_klass(new_klass)
          self.class.new(filepath, selfie, nesting, AnalyzedKlass.new(new_klass, :public), analyzed_method, lenv)
        end

        def with_visibility(new_visibility)
          self.class.new(filepath, selfie, nesting, AnalyzedKlass.new(analyzed_klass.klass, new_visibility), analyzed_method, lenv)
        end

        def with_analyzed_method(new_analyzed_method)
          self.class.new(filepath, selfie, nesting, analyzed_klass, new_analyzed_method, lenv)
        end

        def merge_lenv(new_lenv)
          self.class.new(filepath, selfie, nesting, analyzed_klass, analyzed_method, lenv.merge(new_lenv))
        end

        def lenv_fetch(key)
          lenv.fetch(key)
        end

        def with_lenv(new_lenv)
          self.class.new(filepath, selfie, nesting, analyzed_klass, analyzed_method, new_lenv)
        end

        def almost_equal?(other)
          filepath == other.filepath &&
            selfie == other.selfie &&
            nesting == other.nesting &&
            analyzed_klass == other.analyzed_klass &&
            analyzed_method == other.analyzed_method
        end
      end

      def initialize(graph, worklist, tree)
        @graph = graph
        @worklist = worklist
        @tree = tree
      end

      def process_file(file, filepath)
        ast = Parser::CurrentRuby.parse(file)
        initial_context = Context.new(filepath, Selfie.main, Nesting.empty, Context::AnalyzedKlass.new(nil, :public), nil, {})
        return process(ast, initial_context)
      end

      private

      def process(ast, context)
        return Result.new(nil, context) if ast.nil?

        process_result = case ast.type
        when :lvasgn
          handle_lvasgn(ast, context)
        when :int
          handle_int(ast, context)
        when :float
          handle_float(ast, context)
        when :true
          handle_true(ast, context)
        when :false
          handle_false(ast, context)
        when :nil
          handle_nil(ast, context)
        when :self
          handle_self(ast, context)
        when :array
          handle_array(ast, context)
        when :splat
          handle_splat(ast, context)
        when :str
          handle_str(ast, context)
        when :dstr
          handle_dstr(ast, context)
        when :sym
          handle_sym(ast, context)
        when :dsym
          handle_dsym(ast, context)
        when :regexp
          handle_regexp(ast, context)
        when :hash
          handle_hash(ast, context)
        when :irange
          handle_irange(ast, context)
        when :erange
          handle_erange(ast, context)
        when :back_ref
          handle_ref(ast, context, :backref)
        when :nth_ref
          handle_ref(ast, context, :nthref)
        when :defined?
          handle_defined(ast, context)
        when :begin
          handle_begin(ast, context)
        when :kwbegin
          handle_begin(ast, context)
        when :lvar
          handle_lvar(ast, context)
        when :ivar
          handle_ivar(ast, context)
        when :ivasgn
          handle_ivasgn(ast, context)
        when :cvar
          handle_cvar(ast, context)
        when :cvasgn
          handle_cvasgn(ast, context)
        when :gvar
          handle_gvar(ast, context)
        when :gvasgn
          handle_gvasgn(ast, context)
        when :send
          handle_send(ast, context, false)
        when :csend
          handle_send(ast, context, true)
        when :block
          handle_block(ast, context)
        when :def
          handle_def(ast, context)
        when :defs
          handle_defs(ast, context)
        when :class
          handle_class(ast, context)
        when :sclass
          handle_sclass(ast, context)
        when :module
          handle_module(ast, context)
        when :casgn
          handle_casgn(ast, context)
        when :const
          handle_const(ast, context)
        when :and
          handle_and(ast, context)
        when :or
          handle_or(ast, context)
        when :if
          handle_if(ast, context)
        when :return
          handle_return(ast, context)
        when :masgn
          handle_masgn(ast, context)
        when :alias
          handle_alias(ast, context)
        when :super
          handle_super(ast, context)
        when :zsuper
          handle_zsuper(ast, context)
        when :when
          handle_when(ast, context)
        when :case
          handle_case(ast, context)
        when :yield
          handle_yield(ast, context)
        when :block_pass
          handle_block_pass(ast, context)

        when :while then handle_while(ast, context)
        when :until then handle_while(ast, context)
        when :while_post then handle_while(ast, context)
        when :until_post then handle_while(ast, context)
        when :break then handle_break(ast, context)
        when :next then handle_break(ast, context)
        when :redo then handle_break(ast, context)

        when :rescue then handle_rescue(ast, context)
        when :resbody then handle_resbody(ast, context)
        when :retry then handle_retry(ast, context)
        when :ensure then handle_ensure(ast, context)

        when :op_asgn then handle_op_asgn(ast, context)
        when :or_asgn then handle_or_asgn(ast, context)
        when :and_asgn then handle_and_asgn(ast, context)

        else raise ArgumentError.new(ast.type)
        end

        if process_result.node && !process_result.node.location
          process_result.node.location = build_location_from_ast(context, ast)
        end
        return process_result
      end

      def handle_lvasgn(ast, context)
        var_name = ast.children[0].to_s
        expr = ast.children[1]

        node_lvasgn = add_vertex(Node.new(:lvasgn, { var_name: var_name }, build_location_from_ast(context, ast)))

        if expr
          expr_result = process(expr, context)
          @graph.add_edge(expr_result.node, node_lvasgn)
          final_context = expr_result.context.merge_lenv(var_name => [node_lvasgn])
        else
          final_context = context.merge_lenv(var_name => [node_lvasgn])
        end

        return Result.new(node_lvasgn, final_context)
      end

      def handle_int(ast, context)
        value = ast.children[0]
        n = add_vertex(Node.new(:int, { value: value }, build_location_from_ast(context, ast)))

        return Result.new(n, context)
      end

      def handle_float(ast, context)
        value = ast.children[0]
        n = add_vertex(Node.new(:float, { value: value }, build_location_from_ast(context, ast)))

        return Result.new(n, context)
      end

      def handle_true(ast, context)
        n = add_vertex(Node.new(:bool, { value: true }, build_location_from_ast(context, ast)))

        return Result.new(n, context)
      end

      def handle_false(ast, context)
        n = add_vertex(Node.new(:bool, { value: false }, build_location_from_ast(context, ast)))

        return Result.new(n, context)
      end

      def handle_nil(ast, context)
        n = add_vertex(Node.new(:nil, {}, build_location_from_ast(context, ast)))

        return Result.new(n, context)
      end

      def handle_str(ast, context)
        value = ast.children[0]
        n = add_vertex(Node.new(:str, { value: value }, build_location_from_ast(context, ast)))

        return Result.new(n, context)
      end

      def handle_dstr(ast, context)
        node_dstr = add_vertex(Node.new(:dstr, {}, build_location_from_ast(context, ast)))

        final_context, nodes = fold_context(ast.children, context)
        add_edges(nodes, node_dstr)

        return Result.new(node_dstr, final_context)
      end

      def handle_sym(ast, context)
        value = ast.children[0]
        n = add_vertex(Node.new(:sym, { value: value }, build_location_from_ast(context, ast)))

        return Result.new(n, context)
      end

      def handle_dsym(ast, context)
        node_dsym = add_vertex(Node.new(:dsym, {}, build_location_from_ast(context, ast)))

        final_context, nodes = fold_context(ast.children, context)
        add_edges(nodes, node_dsym)

        return Result.new(node_dsym, final_context)
      end

      def handle_array(ast, context)
        node_array = add_vertex(Node.new(:array, {}, build_location_from_ast(context, ast)))

        final_context, nodes = fold_context(ast.children, context)
        add_edges(nodes, node_array)

        return Result.new(node_array, final_context)
      end

      def handle_splat(ast, context)
        expr = ast.children[0]

        expr_result = process(expr, context)

        node_splat = Node.new(:splat_array, {}, build_location_from_ast(context, ast))
        @graph.add_edge(expr_result.node, node_splat)

        return Result.new(node_splat, expr_result.context)
      end

      def handle_regexp(ast, context)
        expr_nodes = ast.children[0..-2]
        regopt = ast.children[-1]

        node_regexp = Node.new(:regexp, { regopt: regopt.children }, build_location_from_ast(context, ast))

        final_context, nodes = fold_context(expr_nodes, context)
        add_edges(nodes, node_regexp)

        return Result.new(node_regexp, final_context)
      end

      def handle_irange(ast, context)
        common_range(ast, context, true)
      end

      def handle_erange(ast, context)
        common_range(ast, context, false)
      end

      def common_range(ast, context, inclusive)
        range_from_ast = ast.children[0]
        range_to_ast = ast.children[1]

        range_node = Node.new(:range, { inclusive: inclusive }, build_location_from_ast(context, ast))

        range_from_ast_result = process(range_from_ast, context)
        from_node = Node.new(:range_from, {})
        @graph.add_edge(range_from_ast_result.node, from_node)
        @graph.add_edge(from_node, range_node)

        range_to_ast_result = process(range_to_ast, range_from_ast_result.context)
        to_node = Node.new(:range_to, {})
        @graph.add_edge(range_to_ast_result.node, to_node)
        @graph.add_edge(to_node, range_node)

        return Result.new(range_node, range_to_ast_result.context)
      end

      def handle_ref(ast, context, node_type)
        ref = if node_type == :backref
          ast.children[0].to_s[1..-1]
        elsif node_type == :nthref
          ast.children[0].to_s
        else
          raise
        end
        node = add_vertex(Node.new(node_type, { ref: ref }, build_location_from_ast(context, ast)))
        return Result.new(node, context)
      end

      def handle_defined(ast, context)
        _expr = ast.children[0]

        node = add_vertex(Node.new(:defined, {}, build_location_from_ast(context, ast)))

        return Result.new(node, context)
      end

      def handle_begin(ast, context)
        final_context, nodes = fold_context(ast.children, context)
        return Result.new(nodes.last, final_context)
      end

      def handle_lvar(ast, context)
        var_name = ast.children[0].to_s

        node_lvar = add_vertex(Node.new(:lvar, { var_name: var_name }, build_location_from_ast(context, ast)))

        context.lenv_fetch(var_name).each do |var_definition_node|
          @graph.add_edge(var_definition_node, node_lvar)
        end

        return Result.new(node_lvar, context)
      end

      def handle_ivar(ast, context)
        ivar_name = ast.children.first.to_s

        ivar_definition_node = if context.selfie.klass?
          @graph.get_class_level_ivar_definition_node(context.scope, ivar_name)
        elsif context.selfie.instance?
          @graph.get_ivar_definition_node(context.scope, ivar_name)
        elsif context.selfie.main?
          @graph.get_main_ivar_definition_node(ivar_name)
        else
          raise
        end

        node = Node.new(:ivar, { var_name: ivar_name }, build_location_from_ast(context, ast))
        @graph.add_edge(ivar_definition_node, node)

        return Result.new(node, context)
      end

      def handle_ivasgn(ast, context)
        ivar_name = ast.children[0].to_s
        expr = ast.children[1]

        node_ivasgn = add_vertex(Node.new(:ivasgn, { var_name: ivar_name }, build_location_from_ast(context, ast)))

        if expr
          expr_result = process(expr, context)
          @graph.add_edge(expr_result.node, node_ivasgn)
          context_after_expr = expr_result.context
        else
          context_after_expr = context
        end

        ivar_definition_node = if context.selfie.klass?
          @graph.get_class_level_ivar_definition_node(context.scope, ivar_name)
        elsif context.selfie.instance?
          @graph.get_ivar_definition_node(context_after_expr.scope, ivar_name)
        elsif context.selfie.main?
          @graph.get_main_ivar_definition_node(ivar_name)
        else
          raise
        end
        @graph.add_edge(node_ivasgn, ivar_definition_node)

        return Result.new(node_ivasgn, context_after_expr)
      end

      def handle_cvasgn(ast, context)
        cvar_name = ast.children[0].to_s
        expr = ast.children[1]

        node_cvasgn = add_vertex(Node.new(:cvasgn, { var_name: cvar_name }, build_location_from_ast(context, ast)))

        if expr
          expr_result = process(expr, context)
          @graph.add_edge(expr_result.node, node_cvasgn)
          context_after_expr = expr_result.context
        else
          context_after_expr = context
        end

        node_cvar_definition = @graph.get_cvar_definition_node(context.scope, cvar_name)
        @graph.add_edge(node_cvasgn, node_cvar_definition)

        return Result.new(node_cvasgn, context_after_expr)
      end

      def handle_cvar(ast, context)
        cvar_name = ast.children.first.to_s

        cvar_definition_node = @graph.get_cvar_definition_node(context.scope, cvar_name)

        node = Node.new(:cvar, { var_name: cvar_name }, build_location_from_ast(context, ast))
        @graph.add_edge(cvar_definition_node, node)

        return Result.new(node, context)
      end

      def handle_gvasgn(ast, context)
        gvar_name = ast.children[0].to_s
        expr = ast.children[1]

        node_gvasgn = add_vertex(Node.new(:gvasgn, { var_name: gvar_name }, build_location_from_ast(context, ast)))

        expr_result = process(expr, context)
        @graph.add_edge(expr_result.node, node_gvasgn)

        node_gvar_definition = @graph.get_gvar_definition_node(gvar_name)
        @graph.add_edge(node_gvasgn, node_gvar_definition)

        return Result.new(node_gvasgn, expr_result.context)
      end

      def handle_gvar(ast, context)
        gvar_name = ast.children.first.to_s

        gvar_definition_node = @graph.get_gvar_definition_node(gvar_name)

        node = add_vertex(Node.new(:gvar, { var_name: gvar_name }, build_location_from_ast(context, ast)))
        @graph.add_edge(gvar_definition_node, node)

        return Result.new(node, context)
      end

      def handle_send(ast, context, csend)
        obj_expr = ast.children[0]
        message_name = ast.children[1].to_s
        arg_exprs = ast.children[2..-1]

        if obj_expr.nil?
          obj_node = add_vertex(Node.new(:self, { selfie: context.selfie }))
          obj_context = context
        else
          expr_result = process(obj_expr, context)
          obj_node = expr_result.node
          obj_context = expr_result.context
        end

        call_arg_nodes = []
        final_context = arg_exprs.reduce(obj_context) do |current_context, ast_child|
          ast_child_result = process(ast_child, current_context)
          call_arg_node = add_vertex(Node.new(:call_arg))
          call_arg_nodes << call_arg_node
          @graph.add_edge(ast_child_result.node, call_arg_node)
          ast_child_result.context
        end

        return handle_changing_visibility(context, message_name.to_sym, arg_exprs) if obj_expr.nil? && ["public", "protected", "private"].include?(message_name)
        return handle_custom_attr_reader_send(context, arg_exprs, ast) if obj_expr.nil? && message_name == "attr_reader"
        return handle_custom_attr_writer_send(context, arg_exprs, ast) if obj_expr.nil? && message_name == "attr_writer"
        return handle_custom_attr_accessor_send(context, arg_exprs, ast) if obj_expr.nil? && message_name == "attr_accessor"
        return handle_custom_class_send(context, obj_node) if message_name == "class"
        return handle_custom_freeze_send(context, obj_node) if message_name == "freeze"

        call_obj_node = add_vertex(Node.new(:call_obj))
        @graph.add_edge(obj_node, call_obj_node)

        call_result_node = add_vertex(Node.new(:call_result, { csend: csend }))

        message_send = Worklist::MessageSend.new(message_name, call_obj_node, call_arg_nodes, call_result_node, nil)
        @worklist.add_message_send(message_send)

        return Result.new(call_result_node, final_context, { message_send: message_send })
      end

      def handle_custom_class_send(context, obj_node)
        extract_class_node = @graph.add_vertex(Node.new(:extract_class))
        @graph.add_edge(obj_node, extract_class_node)

        return Result.new(extract_class_node, context)
      end

      def handle_custom_freeze_send(context, obj_node)
        freeze_node = @graph.add_vertex(Node.new(:freeze))
        @graph.add_edge(obj_node, freeze_node)

        return Result.new(freeze_node, context)
      end

      def handle_changing_visibility(context, new_visibility, arg_exprs)
        if context.analyzed_klass.klass && arg_exprs.empty?
          final_node = add_vertex(Node.new(:const, { const_ref: ConstRef.from_full_name(context.analyzed_klass.klass.full_name, Nesting.empty) }))
          return Result.new(final_node, context.with_visibility(new_visibility))
        elsif context.analyzed_klass.klass
          methods_to_change_visibility = arg_exprs.map do |arg_expr|
            [:sym, :str].include?(arg_expr.type) ? arg_expr.children[0].to_s : nil
          end.compact
          @tree.metods.each do |m|
            if m.scope == context.scope && methods_to_change_visibility.include?(m.name)
              m.visibility = new_visibility
            end
          end

          final_node = add_vertex(Node.new(:const, { const_ref: ConstRef.from_full_name(context.analyzed_klass.klass.full_name, Nesting.empty) }))
          return Result.new(final_node, context)
        else
          final_node = add_vertex(Node.new(:const, { const_ref: ConstRef.from_full_name("Object", Nesting.empty) }))
          return Result.new(final_node, context)
        end
      end

      def handle_custom_attr_reader_send(context, arg_exprs, ast)
        location = build_location_from_ast(context, ast)
        ivar_names = arg_exprs.select {|s| [:sym, :str].include?(s.type) }.map {|s| s.children.first }.map(&:to_s)
        ivar_names.each do |ivar_name|
          define_attr_reader_method(context, ivar_name, location)
        end

        return Result.new(Node.new(:nil), context)
      end

      def handle_custom_attr_writer_send(context, arg_exprs, ast)
        location = build_location_from_ast(context, ast)
        ivar_names = arg_exprs.select {|s| [:sym, :str].include?(s.type) }.map {|s| s.children.first }.map(&:to_s)
        ivar_names.each do |ivar_name|
          define_attr_writer_method(context, ivar_name, location)
        end

        return Result.new(Node.new(:nil), context)
      end

      def handle_custom_attr_accessor_send(context, arg_exprs, ast)
        location = build_location_from_ast(context, ast)
        ivar_names = arg_exprs.select {|s| [:sym, :str].include?(s.type) }.map {|s| s.children.first }.map(&:to_s)
        ivar_names.each do |ivar_name|
          define_attr_reader_method(context, ivar_name, location)
          define_attr_writer_method(context, ivar_name, location)
        end

        return Result.new(Node.new(:nil), context)
      end

      def define_attr_reader_method(context, ivar_name, location)
        ivar_definition_node = @graph.get_ivar_definition_node(context.scope, "@#{ivar_name}")

        metod = @tree.add_method(
          GlobalTree::Method.new(
            scope: context.scope,
            name: ivar_name,
            location: location,
            args: GlobalTree::Method::ArgumentsTree.new([], [], nil),
            visibility: context.analyzed_klass.method_visibility,
            nodes: GlobalTree::Method::Nodes.new([], add_vertex(Node.new(:method_result)), [])))
        @graph.add_edge(ivar_definition_node, metod.nodes.result)
      end

      def define_attr_writer_method(context, ivar_name, location)
        ivar_definition_node = @graph.get_ivar_definition_node(context.scope, "@#{ivar_name}")

        arg_name = "_attr_writer"
        arg_node = add_vertex(Node.new(:formal_arg, { var_name: arg_name }))
        metod = @tree.add_method(
          GlobalTree::Method.new(
            scope: context.scope,
            name: "#{ivar_name}=",
            location: location,
            args: GlobalTree::Method::ArgumentsTree.new([GlobalTree::Method::ArgumentsTree::Regular.new(arg_name)], [], nil),
            visibility: context.analyzed_klass.method_visibility,
            nodes: GlobalTree::Method::Nodes.new({arg_name => arg_node}, add_vertex(Node.new(:method_result)), [])))
        @graph.add_edge(arg_node, ivar_definition_node)
        @graph.add_edge(ivar_definition_node, metod.nodes.result)
      end

      def handle_self(ast, context)
        node = add_vertex(Node.new(:self, { selfie: context.selfie }, build_location_from_ast(context, ast)))
        return Result.new(node, context)
      end

      def handle_block(ast, context)
        send_expr = ast.children[0]
        args_ast = ast.children[1]
        block_expr = ast.children[2]

        if send_expr == Parser::AST::Node.new(:send, [nil, :lambda])
          send_context = context
        else
          send_expr_result = process(send_expr, context)
          message_send = send_expr_result.data.fetch(:message_send)
          send_node = send_expr_result.node
          send_context = send_expr_result.context
        end

        args_ast_nodes = []
        context_with_args = args_ast.children.reduce(send_context) do |current_context, arg_ast|
          arg_node = add_vertex(Node.new(:block_arg, {}, build_location_from_ast(context, arg_ast)))
          args_ast_nodes << arg_node
          case arg_ast.type
          when :arg
            arg_name = arg_ast.children[0].to_s
            current_context.merge_lenv(arg_name => [arg_node])
          when :mlhs
            handle_mlhs_for_block(arg_ast, current_context, arg_node)
          else raise RuntimeError.new(ast)
          end
        end

        # It's not exactly good - local vars defined in blocks are not available outside (?),
        #     but assignments done in blocks are valid.
        block_expr_result = process(block_expr, context_with_args)
        block_final_node = block_expr_result.node
        block_result_context = block_expr_result.context
        block_result_node = add_vertex(Node.new(:block_result))
        @graph.add_edge(block_final_node, block_result_node)

        if send_expr == Parser::AST::Node.new(:send, [nil, :lambda])
          lamb = @tree.add_lambda(GlobalTree::Lambda::Nodes.new(args_ast_nodes, block_result_node))
          lambda_node = add_vertex(Node.new(:lambda, { id: lamb.id }))
          return Result.new(lambda_node, block_result_context)
        else
          block = Block.new(args_ast_nodes, block_result_node)
          message_send.block = block
          return Result.new(send_node, block_result_context)
        end
      end

      def handle_mlhs_for_block(ast, context, node)
        unwrap_array_node = Node.new(:unwrap_array)
        @graph.add_edge(node, unwrap_array_node)

        final_context = ast.children.reduce(context) do |current_context, ast_child|
          case ast_child.type
          when :arg
            arg_name = ast_child.children[0].to_s
            current_context.merge_lenv(arg_name => [unwrap_array_node])
          when :mlhs
            handle_mlhs_for_block(ast_child, current_context, unwrap_array_node)
          else raise
          end
        end

        return final_context
      end

      def handle_def(ast, context)
        method_name = ast.children[0]
        formal_arguments = ast.children[1]
        method_body = ast.children[2]

        arguments_tree, arguments_context, arguments_nodes = build_def_arguments(formal_arguments.children, context)

        metod = @tree.add_method(
          GlobalTree::Method.new(
            scope: context.scope,
            name: method_name.to_s,
            location: build_location(context, Position.new(ast.loc.line, nil), Position.new(ast.loc.line, nil)),
            args: arguments_tree,
            visibility: context.analyzed_klass.method_visibility,
            nodes: GlobalTree::Method::Nodes.new(arguments_nodes, add_vertex(Node.new(:method_result)), [])))

        context.with_analyzed_method(metod).tap do |context2|
          if method_body
            context2.with_selfie(Selfie.instance_from_scope(context2.scope)).tap do |context3|
              final_node = process(method_body, context3.merge_lenv(arguments_context.lenv)).node
              @graph.add_edge(final_node, context3.analyzed_method.nodes.result)
            end
          else
            final_node = add_vertex(Node.new(:nil))
            @graph.add_edge(final_node, context2.analyzed_method.nodes.result)
          end
        end

        node = add_vertex(Node.new(:sym, { value: method_name }, build_location_from_ast(context, ast)))

        return Result.new(node, context)
      end

      def handle_hash(ast, context)
        node_hash_keys = add_vertex(Node.new(:hash_keys))
        node_hash_values = add_vertex(Node.new(:hash_values))
        node_hash = add_vertex(Node.new(:hash))
        @graph.add_edge(node_hash_keys, node_hash)
        @graph.add_edge(node_hash_values, node_hash)

        final_context = ast.children.reduce(context) do |current_context, ast_child|
          case ast_child.type
          when :pair
            hash_key, hash_value = ast_child.children
            hash_key_result = process(hash_key, current_context)
            hash_value_result = process(hash_value, hash_key_result.context)
            @graph.add_edge(hash_key_result.node, node_hash_keys)
            @graph.add_edge(hash_value_result.node, node_hash_values)
            hash_value_result.context
          when :kwsplat
            kwsplat_expr = ast_child.children[0]

            kwsplat_expr_result = process(kwsplat_expr, context)

            node_unwrap_hash_keys = Node.new(:unwrap_hash_keys)
            node_unwrap_hash_values = Node.new(:unwrap_hash_values)

            @graph.add_edge(kwsplat_expr_result.node, node_unwrap_hash_keys)
            @graph.add_edge(kwsplat_expr_result.node, node_unwrap_hash_values)

            @graph.add_edge(node_unwrap_hash_keys, node_hash_keys)
            @graph.add_edge(node_unwrap_hash_values, node_hash_values)

            kwsplat_expr_result.context
          else raise ArgumentError.new(ast)
          end
        end

        return Result.new(node_hash, final_context)
      end

      def handle_class(ast, context)
        klass_name_ast, parent_klass_name_ast, klass_body = ast.children
        klass_name_ref = ConstRef.from_ast(klass_name_ast, context.nesting)
        parent_name_ref = parent_klass_name_ast.nil? ? nil : ConstRef.from_ast(parent_klass_name_ast, context.nesting)

        klass = @tree.add_klass(
          GlobalTree::Klass.new(
            name: klass_name_ref.name,
            scope: context.scope.increase_by_ref(klass_name_ref).decrease,
            parent_ref: parent_name_ref,
            location: build_location(context, Position.new(klass_name_ast.loc.line, nil), Position.new(klass_name_ast.loc.line, nil))))

        new_context = context
          .with_analyzed_klass(klass)
          .with_nesting(context.nesting.increase_nesting_const(klass_name_ref))
          .with_selfie(Selfie.klass_from_scope(context.scope))
        if klass_body
          process(klass_body, new_context)
        end

        node = add_vertex(Node.new(:nil))

        return Result.new(node, context)
      end

      def handle_module(ast, context)
        module_name_ast = ast.children[0]
        module_body = ast.children[1]

        module_name_ref = ConstRef.from_ast(module_name_ast, context.nesting)

        @tree.add_mod(
          GlobalTree::Mod.new(
            name: module_name_ref.name,
            scope: context.scope.increase_by_ref(module_name_ref).decrease,
            location: build_location(context, Position.new(module_name_ast.loc.line, nil), Position.new(module_name_ast.loc.line, nil))))

        if module_body
          context.with_nesting(context.nesting.increase_nesting_const(module_name_ref)).tap do |context2|
            process(module_body, context2)
          end
        end

        return Result.new(Node.new(:nil), context)
      end

      def handle_sclass(ast, context)
        self_name = ast.children[0]
        sklass_body = ast.children[1]
        process(sklass_body, context.with_nesting(context.nesting.increase_nesting_self))

        return Result.new(Node.new(:nil), context)
      end

      def handle_defs(ast, context)
        method_receiver = ast.children[0]
        method_name = ast.children[1]
        formal_arguments = ast.children[2]
        method_body = ast.children[3]

        arguments_tree, arguments_context, arguments_nodes = build_def_arguments(formal_arguments.children, context)

        metod = @tree.add_method(
          GlobalTree::Method.new(
            scope: context.scope.increase_by_metaklass,
            name: method_name.to_s,
            location: build_location(context, Position.new(ast.loc.line, nil), Position.new(ast.loc.line, nil)),
            args: arguments_tree,
            visibility: context.analyzed_klass.method_visibility,
            nodes: GlobalTree::Method::Nodes.new(arguments_nodes, add_vertex(Node.new(:method_result)), [])))

        context.with_analyzed_method(metod).tap do |context2|
          if method_body
            context2.with_selfie(Selfie.klass_from_scope(context2.scope)).tap do |context3|
              final_node = process(method_body, context3.merge_lenv(arguments_context.lenv)).node
              @graph.add_edge(final_node, context3.analyzed_method.nodes.result)
            end
          else
            final_node = add_vertex(Node.new(:nil))
            @graph.add_edge(final_node, context2.analyzed_method.nodes.result)
          end
        end

        node = add_vertex(Node.new(:sym, { value: method_name }))

        return Result.new(node, context)
      end

      def handle_casgn(ast, context)
        const_prename, const_name, expr = ast.children
        const_name_ref = ConstRef.from_full_name(AstUtils.const_prename_and_name_to_string(const_prename, const_name), context.nesting)

        if expr_is_class_definition?(expr)
          parent_klass_name_ast = expr.children[2]
          parent_name_ref = parent_klass_name_ast.nil? ? nil : ConstRef.from_ast(parent_klass_name_ast, context.nesting)
          @tree.add_klass(
            GlobalTree::Klass.new(
              name: const_name_ref.name,
              scope: context.scope.increase_by_ref(const_name_ref).decrease,
              parent_ref: parent_name_ref,
              location: build_location(context, Position.new(ast.loc.line, nil), Position.new(ast.loc.line, nil))))

          return Result.new(Node.new(:nil), context)
        elsif expr_is_module_definition?(expr)
          @tree.add_mod(
            GlobalTree::Mod.new(
              name: const_name_ref.name,
              scope: context.scope.increase_by_ref(const_name_ref).decrease,
              location: build_location(context, Position.new(ast.loc.line, nil), Position.new(ast.loc.line, nil))))

          return Result.new(Node.new(:nil), context)
        else
          @tree.add_constant(
            GlobalTree::Constant.new(
              name: const_name_ref.name,
              scope: context.scope.increase_by_ref(const_name_ref).decrease,
              location: build_location(context, Position.new(ast.loc.line, nil), Position.new(ast.loc.line, nil))))

          expr_result = process(expr, context)

          final_node = Node.new(:casgn, { const_ref: const_name_ref })
          @graph.add_edge(expr_result.node, final_node)

          const_name = context.scope.increase_by_ref(const_name_ref).to_const_name
          node_const_definition = @graph.get_constant_definition_node(const_name.to_string)
          @graph.add_edge(final_node, node_const_definition)

          return Result.new(final_node, expr_result.context)
        end
      end

      def handle_const(ast, context)
        const_ref = ConstRef.from_ast(ast, context.nesting)

        node = add_vertex(Node.new(:const, { const_ref: const_ref }))

        return Result.new(node, context)
      end

      def handle_and(ast, context)
        handle_binary_operator(:and, ast.children[0], ast.children[1], context)
      end

      def handle_or(ast, context)
        handle_binary_operator(:or, ast.children[0], ast.children[1], context)
      end

      def handle_binary_operator(node_type, expr_left, expr_right, context)
        expr_left_result = process(expr_left, context)
        expr_right_result = process(expr_right, expr_left_result.context)

        node_or = add_vertex(Node.new(node_type))
        @graph.add_edge(expr_left_result.node, node_or)
        @graph.add_edge(expr_right_result.node, node_or)

        return Result.new(node_or, expr_right_result.context)
      end

      def handle_if(ast, context)
        expr_cond = ast.children[0]
        expr_iftrue = ast.children[1]
        expr_iffalse = ast.children[2]

        expr_cond_result = process(expr_cond, context)

        if expr_iftrue
          expr_iftrue_result = process(expr_iftrue, expr_cond_result.context)

          node_iftrue = expr_iftrue_result.node
          context_after_iftrue = expr_iftrue_result.context
        else
          node_iftrue = add_vertex(Node.new(:nil))
          context_after_iftrue = context
        end

        if expr_iffalse
          expr_iffalse_result = process(expr_iffalse, expr_cond_result.context)

          node_iffalse = expr_iffalse_result.node
          context_after_iffalse = expr_iffalse_result.context
        else
          node_iffalse = add_vertex(Node.new(:nil))
          context_after_iffalse = context
        end

        node_if_result = add_vertex(Node.new(:if_result))
        @graph.add_edge(node_iftrue, node_if_result)
        @graph.add_edge(node_iffalse, node_if_result)

        return Result.new(node_if_result, merge_contexts(context_after_iftrue, context_after_iffalse))
      end

      def handle_return(ast, context)
        exprs = ast.children

        if exprs.size == 0
          node_expr = add_vertex(Node.new(:nil))
          final_context = context
        elsif exprs.size == 1
          expr_result = process(exprs[0], context)
          node_expr = expr_result.node
          final_context = expr_result.context
        else
          node_expr = add_vertex(Node.new(:array))
          final_context, nodes = fold_context(ast.children, context)
          add_edges(nodes, node_expr)
        end
        @graph.add_edge(node_expr, context.analyzed_method.nodes.result)

        return Result.new(node_expr, final_context)
      end

      def handle_masgn(ast, context)
        mlhs_expr = ast.children[0]
        rhs_expr = ast.children[1]

        rhs_expr_result = process(rhs_expr, context)
        node_rhs = rhs_expr_result.node
        context_after_rhs = rhs_expr_result.context

        mlhs_result = handle_mlhs_for_masgn(mlhs_expr, context, rhs_expr)

        return mlhs_result
      end

      def handle_mlhs_for_masgn(ast, context, rhs_expr)
        result_node = add_vertex(Node.new(:array))

        i = 0
        final_context = ast.children.reduce(context) do |current_context, ast_child|
          if ast_child.type == :mlhs
            new_rhs_expr = Parser::AST::Node.new(:send, [rhs_expr, :[], Parser::AST::Node.new(:int, [i])])
            ast_child_result = handle_mlhs_for_masgn(ast_child, current_context, new_rhs_expr)
            node_child = ast_child_result.node
            context_after_child = ast_child_result.context
          else
            new_ast_child = ast_child.append(Parser::AST::Node.new(:send, [rhs_expr, :[], Parser::AST::Node.new(:int, [i])]))
            new_ast_child_result = process(new_ast_child, current_context)
            node_child = new_ast_child_result.node
            context_after_child = new_ast_child_result.context
          end

          @graph.add_edge(node_child, result_node)
          i += 1
          context_after_child
        end

        return Result.new(result_node, final_context)
      end

      def handle_alias(ast, context)
        node = add_vertex(Node.new(:nil))
        return Result.new(node, context)
      end

      def handle_super(ast, context)
        arg_exprs = ast.children

        call_arg_nodes = []
        final_context = arg_exprs.reduce(context) do |current_context, ast_child|
          ast_child_result = process(ast_child, current_context)
          call_arg_node = add_vertex(Node.new(:call_arg))
          call_arg_nodes << call_arg_node
          @graph.add_edge(ast_child_result.node, call_arg_node)
          ast_child_result.context
        end

        call_result_node = add_vertex(Node.new(:call_result))

        super_send = Worklist::SuperSend.new(call_arg_nodes, call_result_node, nil)
        @worklist.add_message_send(super_send)

        return Result.new(call_result_node, final_context, { message_send: super_send })
      end

      def handle_zsuper(ast, context)
        call_result_node = add_vertex(Node.new(:call_result))

        zsuper_send = Worklist::Super0Send.new(call_result_node, nil)
        @worklist.add_message_send(zsuper_send)

        return Result.new(call_result_node, context, { message_send: zsuper_send })
      end

      def handle_while(ast, context)
        expr_cond = ast.children[0]
        expr_body = ast.children[1]

        new_context = process(expr_cond, context).context
        final_context = process(expr_body, new_context).context

        node = add_vertex(Node.new(:nil))

        return Result.new(node, final_context)
      end

      def handle_case(ast, context)
        expr_cond = ast.children[0]
        expr_branches = ast.children[1..-1].compact

        new_context = process(expr_cond, context).context

        node_case_result = add_vertex(Node.new(:case_result))
        final_context = expr_branches.reduce(new_context) do |current_context, expr_when|
          expr_when_result = process(expr_when, current_context)
          @graph.add_edge(expr_when_result.node, node_case_result)
          expr_when_result.context
        end

        return Result.new(node_case_result, final_context)
      end

      def handle_yield(ast, context)
        exprs = ast.children

        node_yield = add_vertex(Node.new(:yield))
        final_context = if exprs.empty?
          @graph.add_edge(Node.new(:nil), node_yield)
          context
        else
          exprs.reduce(context) do |current_context, current_expr|
            current_expr_result = process(current_expr, current_context)
            @graph.add_edge(current_expr_result.node, node_yield)
            current_expr_result.context
          end
        end
        if context.analyzed_method
          context.analyzed_method.nodes.yields << node_yield
        end
        result_node = add_vertex(Node.new(:nil))

        return Result.new(result_node, final_context)
      end

      def handle_when(ast, context)
        expr_cond = ast.children[0]
        expr_body = ast.children[1]

        context_after_cond = process(expr_cond, context).context
        expr_body_result = process(expr_body, context_after_cond)

        return Result.new(expr_body_result.node, expr_body_result.context)
      end

      def handle_break(ast, context)
        return Result.new(Node.new(:bottom), context)
      end

      def handle_block_pass(ast, context)
        expr = ast.children[0]

        expr_result = process(expr, context)

        return expr_result
      end

      def handle_resbody(ast, context)
        error_array_expr = ast.children[0]
        assignment_expr = ast.children[1]
        rescue_body_expr = ast.children[2]

        context_after_errors = if error_array_expr
          error_array_expr_result = process(error_array_expr, context)
          unwrap_node = add_vertex(Node.new(:unwrap_array))
          @graph.add_edge(error_array_expr_result.node, unwrap_node)
          error_array_expr_result.context
        else
          context
        end

        context_after_assignment = if assignment_expr
          assignment_expr_result = process(assignment_expr, context_after_errors)
          @graph.add_edge(unwrap_node, assignment_expr_result.node) if unwrap_node
          assignment_expr_result.context
        else
          context
        end

        if rescue_body_expr
          rescue_body_expr_result = process(rescue_body_expr, context_after_assignment)
          node_rescue_body = rescue_body_expr_result.node
          final_context = rescue_body_expr_result.context
        else
          node_rescue_body = add_vertex(Node.new(:nil))
          final_context = context
        end

        return Result.new(node_rescue_body, final_context)
      end

      def handle_rescue(ast, context)
        try_expr = ast.children[0]
        resbody = ast.children[1]
        elsebody = ast.children[2]

        if try_expr
          try_expr_result = process(try_expr, context)
          node_try = try_expr_result.node
          context_after_try = try_expr_result.context
        else
          node_try = add_vertex(Node.new(:nil))
          context_after_try = context
        end

        resbody_result = process(resbody, context_after_try)
        node_resbody = resbody_result.node
        context_after_resbody = resbody_result.context

        node = add_vertex(Node.new(:rescue))
        @graph.add_edge(node_resbody, node)

        if elsebody
          elsebody_result = process(elsebody, context_after_try)
          node_else = elsebody_result.node
          context_after_else = elsebody_result.context
          @graph.add_edge(node_else, node)
          return Result.new(node, merge_contexts(context_after_resbody, context_after_else))
        else
          @graph.add_edge(node_try, node)
          return Result.new(node, context_after_resbody)
        end
      end

      def handle_retry(ast, context)
        return Result.new(add_vertex(Node.new(:bottom)), context)
      end

      def handle_ensure(ast, context)
        expr_pre = ast.children[0]
        expr_ensure_body = ast.children[1]

        node_ensure = add_vertex(Node.new(:ensure))

        expr_pre_result = process(expr_pre, context)
        @graph.add_edge(expr_pre_result.node, node_ensure) if expr_pre_result.node

        expr_ensure_body_result = process(expr_ensure_body, expr_pre_result.context)
        @graph.add_edge(expr_ensure_body_result.node, node_ensure) if expr_ensure_body_result.node

        return Result.new(node_ensure, expr_ensure_body_result.context)
      end

      def handle_op_asgn(ast, context)
        expr_partial_asgn = ast.children[0]
        method_name = ast.children[1]
        expr_argument = ast.children[2]

        case expr_partial_asgn.type
        when :lvasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:send,
                                                [Parser::AST::Node.new(:lvar, [var_name]), method_name, expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :ivasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:send,
                                                [Parser::AST::Node.new(:ivar, [var_name]), method_name, expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :cvasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:send,
                                                [Parser::AST::Node.new(:cvar, [var_name]), method_name, expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :casgn
          scope = expr_partial_asgn.children[0]
          var_name = expr_partial_asgn.children[1]
          expr_full_rhs = Parser::AST::Node.new(:send,
                                                [Parser::AST::Node.new(:const, [scope, var_name]), method_name, expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :send
          send_obj = expr_partial_asgn.children[0]
          asgn_method_name = expr_partial_asgn.children[1]
          args = expr_partial_asgn.children[2..-1]
          expr_full_rhs = Parser::AST::Node.new(:send,
                                                [Parser::AST::Node.new(:send, [send_obj, asgn_method_name, *args]), method_name, expr_argument])
          expr_full_asgn = expr_partial_asgn.updated(nil, [send_obj, "#{asgn_method_name}=", expr_full_rhs])
        else raise ArgumentError
        end
        expr_full_asgn_result = process(expr_full_asgn, context)

        return expr_full_asgn_result
      end

      def handle_or_asgn(ast, context)
        expr_partial_asgn = ast.children[0]
        expr_argument = ast.children[1]

        case expr_partial_asgn.type
        when :lvasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:or,
                                                [Parser::AST::Node.new(:lvar, [var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :ivasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:or,
                                                [Parser::AST::Node.new(:ivar, [var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :cvasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:or,
                                                [Parser::AST::Node.new(:cvar, [var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :casgn
          scope = expr_partial_asgn.children[0]
          var_name = expr_partial_asgn.children[1]
          expr_full_rhs = Parser::AST::Node.new(:or,
                                                [Parser::AST::Node.new(:const, [scope, var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :send
          send_obj = expr_partial_asgn.children[0]
          asgn_method_name = expr_partial_asgn.children[1]
          args = expr_partial_asgn.children[2..-1]
          expr_full_rhs = Parser::AST::Node.new(:or,
                                                [Parser::AST::Node.new(:send, [send_obj, asgn_method_name, *args]), expr_argument])
          expr_full_asgn = expr_partial_asgn.updated(nil, [send_obj, "#{asgn_method_name}=", expr_full_rhs])
        else raise ArgumentError
        end
        expr_full_asgn_result = process(expr_full_asgn, context)

        return expr_full_asgn_result
      end

      def handle_and_asgn(ast, context)
        expr_partial_asgn = ast.children[0]
        expr_argument = ast.children[1]

        case expr_partial_asgn.type
        when :lvasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:and,
                                                [Parser::AST::Node.new(:lvar, [var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :ivasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:and,
                                                [Parser::AST::Node.new(:ivar, [var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :cvasgn
          var_name = expr_partial_asgn.children[0]
          expr_full_rhs = Parser::AST::Node.new(:and,
                                                [Parser::AST::Node.new(:cvar, [var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :casgn
          scope = expr_partial_asgn.children[0]
          var_name = expr_partial_asgn.children[1]
          expr_full_rhs = Parser::AST::Node.new(:and,
                                                [Parser::AST::Node.new(:const, [scope, var_name]), expr_argument])
          expr_full_asgn = expr_partial_asgn.append(expr_full_rhs)
        when :send
          send_obj = expr_partial_asgn.children[0]
          asgn_method_name = expr_partial_asgn.children[1]
          args = expr_partial_asgn.children[2..-1]
          expr_full_rhs = Parser::AST::Node.new(:and,
                                                [Parser::AST::Node.new(:send, [send_obj, asgn_method_name, *args]), expr_argument])
          expr_full_asgn = expr_partial_asgn.updated(nil, [send_obj, "#{asgn_method_name}=", expr_full_rhs])
        else raise ArgumentError
        end
        expr_full_asgn_result = process(expr_full_asgn, context)

        return expr_full_asgn_result
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

      def build_def_arguments(formal_arguments, context)
        args = []
        kwargs = []
        blockarg = nil

        nodes = {}

        final_context = formal_arguments.reduce(context) do |current_context, arg_ast|
          arg_name = arg_ast.children[0]&.to_s
          maybe_arg_default_expr = arg_ast.children[1]
          location = build_location_from_ast(current_context, arg_ast)

          case arg_ast.type
          when :arg
            args << GlobalTree::Method::ArgumentsTree::Regular.new(arg_name)
            nodes[arg_name] = add_vertex(Node.new(:formal_arg, { var_name: arg_name }, location))
            current_context.merge_lenv(arg_name => [nodes[arg_name]])
          when :optarg
            args << GlobalTree::Method::ArgumentsTree::Optional.new(arg_name)
            maybe_arg_default_expr_result = process(maybe_arg_default_expr, current_context)
            nodes[arg_name] = add_vertex(Node.new(:formal_optarg, { var_name: arg_name }, location))
            @graph.add_edge(maybe_arg_default_expr_result.node, nodes[arg_name])
            maybe_arg_default_expr_result.context.merge_lenv(arg_name => [nodes[arg_name]])
          when :restarg
            args << GlobalTree::Method::ArgumentsTree::Splat.new(arg_name)
            nodes[arg_name] = add_vertex(Node.new(:formal_restarg, { var_name: arg_name }, location))
            current_context.merge_lenv(arg_name => [nodes[arg_name]])
          when :kwarg
            kwargs << GlobalTree::Method::ArgumentsTree::Regular.new(arg_name)
            nodes[arg_name] = add_vertex(Node.new(:formal_kwarg, { var_name: arg_name }, location))
            current_context.merge_lenv(arg_name => [nodes[arg_name]])
          when :kwoptarg
            kwargs << GlobalTree::Method::ArgumentsTree::Optional.new(arg_name)
            maybe_arg_default_expr_result = process(maybe_arg_default_expr, current_context)
            nodes[arg_name] = add_vertex(Node.new(:formal_kwoptarg, { var_name: arg_name }, location))
            @graph.add_edge(maybe_arg_default_expr_result.node, nodes[arg_name])
            maybe_arg_default_expr_result.context.merge_lenv(arg_name => [nodes[arg_name]])
          when :kwrestarg
            kwargs << GlobalTree::Method::ArgumentsTree::Splat.new(arg_name)
            nodes[arg_name] = add_vertex(Node.new(:formal_kwrestarg, { var_name: arg_name }, location))
            current_context.merge_lenv(arg_name => [nodes[arg_name]])
          when :mlhs
            mlhs_node = add_vertex(Node.new(:formal_mlhs, {}, location))
            nested_arg, next_context = build_def_arguments_nested(arg_ast.children, nodes, current_context, mlhs_node)
            args << nested_arg
            next_context
          else raise
          end
        end

        return GlobalTree::Method::ArgumentsTree.new(args, kwargs, blockarg), final_context, nodes
      end

      def build_def_arguments_nested(arg_asts, nodes, context, mlhs_node)
        args = []

        final_context = arg_asts.reduce(context) do |current_context, arg_ast|
          arg_name = arg_ast.children[0]&.to_s

          case arg_ast.type
          when :arg
            args << GlobalTree::Method::ArgumentsTree::Regular.new(arg_name)
            nodes[arg_name] = add_vertex(Node.new(:formal_arg, { var_name: arg_name }))
            current_context.merge(arg_name => [nodes[arg_name]])
          when :restarg
            args << GlobalTree::Method::ArgumentsTree::Splat.new(arg_name)
            nodes[arg_name] = add_vertex(Node.new(:formal_restarg, { var_name: arg_name }))
            current_context.merge(arg_name => [nodes[arg_name]])
          when :mlhs
            mlhs_node = add_vertex(Node.new(:formal_mlhs))
            nested_arg, next_context = build_def_arguments_nested(arg_ast.children, nodes, current_context, mlhs_node)
            args << nested_arg
            next_context
          else raise
          end
        end

        return ArgumentsTree::Nested.new(args), final_context
      end

      def merge_contexts(context1, context2)
        raise if !context1.almost_equal?(context2)
        final_lenv = {}

        var_names = (context1.lenv.keys + context2.lenv.keys).uniq
        var_names.each do |var_name|
          final_lenv[var_name] = context1.lenv.fetch(var_name, []) + context2.lenv.fetch(var_name, [])
        end

        context1.with_lenv(final_lenv)
      end

      def fold_context(exprs, context)
        nodes = []
        final_context = exprs.reduce(context) do |current_context, ast_child|
          child_result = process(ast_child, current_context)
          nodes << child_result.node
          child_result.context
        end
        return final_context, nodes
      end

      def build_location(context, pstart, pend)
        Location.new(context.filepath, PositionRange.new(pstart, pend))
      end

      def build_location_from_ast(context, ast)
        if ast.loc
          Location.new(
            context.filepath,
            PositionRange.new(
              Position.new(ast.loc.expression.begin.line, ast.loc.expression.begin.column + 1),
              Position.new(ast.loc.expression.end.line, ast.loc.expression.end.column + 1)))
        end
      end

      def add_vertex(v)
        @graph.add_vertex(v)
      end

      def add_edges(xs, ys)
        @graph.add_edges(xs, ys)
      end
    end
  end
end
