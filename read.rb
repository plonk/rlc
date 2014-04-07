# -*- coding: utf-8 -*-
require_relative 'util.rb'

class String
  # def inspect
  #   to_s
  # end
end

class Object
  def apply(*more_args, &f)
    f.call(self, *more_args)
  end

  def recur(*more_args, &blk)
    f = lambda { |*args| blk.(f, *args) }
    blk.(f, self, *more_args)
  end
end

class Array
  def butlast
    self[0..-2]
  end

  def rest
    self[1..-1]
  end

  def top
    last
  end
end

$MACROS = {}

module RubyLisp
  def RubyLisp.builtin_stuff
    <<EOF
(defmacro unless (condition &rest body)
  (.list (quote if) condition
     (quote nil)
     (+ (.list (quote progn)) body)))

(defmacro when (condition &rest body)
  (.list (quote if) condition
           (+ (.list (quote progn)) body)
           (quote nil)))

(defmacro rotatef (a b)
  (.list (quote progn)
           (.list (quote setq) (quote tmp) a)
           (.list (quote setq) a b)
           (.list (quote setq) b (quote tmp))
           (quote nil)))

(def list (&rest items)
  items)
EOF
  end

  def RubyLisp.lisp_eval(str, env)
    read_from_string(str)
      .map {|sexp| macroexpand(sexp) }
      .apply(&method(:compile))
      .apply { |ruby_code|
      eval(ruby_code, env)
    }
  end

  # Read Eval Print Loop
  def RubyLisp.repl()
    require 'readline'

    env = TOPLEVEL_BINDING
    lisp_eval(builtin_stuff, env)
    while line = Readline.readline("> ", true)
      begin
        list_of_sexps = read_from_string(line)
        list_of_sexps = list_of_sexps.map {|sexp| macroexpand(sexp) }
        ruby_code = compile(list_of_sexps)

        # puts ruby_code

        result = eval(ruby_code, env)

        # puts
        p result
      rescue StandardError => e
        raise
        p e
      end
    end
  end

  def RubyLisp.compile(ls)
    ls.map { |sexp| compile_sexp(sexp) }.join("\n")
  end

  def RubyLisp.special_form?
  end

  def RubyLisp.compile_lambda_list(ls)
    if (i = ls.index(:"&rest")) != nil
      ls.delete(:"&rest")
    end
    result = ls.map(&:to_s)
    if i
      result[i] = "*" + result[i]
    end
    result.join(', ')
  end

  def RubyLisp.arglist(list)
    if list.empty?
      ""
    else
      "(" + list.join(', ') + ")"
    end
  end

  def RubyLisp.compile_def(name, lambda_list, *body)
    "def " + name.to_s + ' ' + RubyLisp.compile_lambda_list(lambda_list) + "; " + body.map(&method(:compile_sexp)).join('; ') + " end\n"
  end

  def RubyLisp.compile_defmacro(name, lambda_list, *body)
    "$MACROS[:#{name}] = " +
      "lambda { |#{compile_lambda_list(lambda_list)}| " +
      body.map(&method(:compile_sexp)).join("; ") + " }"
  end

  # sexp がリストなら関数呼出。
  # (map (quote ("abc" "def")) & (lambda (x) (upcase x)))
  def RubyLisp.compile_sexp(sexp)
    if sexp.is_a? Array
      if sexp[0] == :quote
        sexp[1].inspect
      elsif sexp[0] == :setq 
        var = compile_sexp(sexp[1])
        val = compile_sexp(sexp[2])
        "#{var} = #{val}"
      elsif sexp[0] == :"if"
        condition = sexp[1]
        thenclause = sexp[2]
        elseclause = sexp[3]
        "if #{compile_sexp(condition)} then #{compile_sexp(thenclause)}" +
          if elseclause
          then " else #{compile_sexp(elseclause)} end"
          else " end" end
      elsif sexp[0] == :progn
        '(' + sexp[1..-1].map(&method(:compile_sexp)).join('; ') + ')'
      elsif sexp[0] == :lambda
        lmd, lambda_list, *rest = sexp
        args = compile_lambda_list(lambda_list)
        "lambda { |#{args}| #{rest.map{|x| compile_sexp(x)}.join('; ')} } "
      elsif sexp[0] == :def
        compile_def(*sexp[1..-1])
      elsif sexp[0] == :defmacro
        compile_defmacro(*sexp[1..-1])
      else
        # この段階で sexp は [:msg, :receiver, :arg1, :arg2, ...] のよ
        # うになっている。
        #
        # 直後の引数がブロック引数であって、通常と異なる経路で渡さなけ
        # ればならないことを指示する & シンボルがあれば、そのようにする。
        if sexp[0].to_s =~ /^global-/
          if sexp.include?(:&)
            raise "too many &'s" if sexp.count(:&) > 1
            raise "& found but not argument" if sexp.index(:&) == sexp.size-1
            posamp = sexp.index(:&)
            func = sexp[posamp+1]
            sexp = sexp.values_at(*(0..sexp.size-1).to_a - [posamp, posamp+1])
            msg, *args = sexp
            msg.to_s.sub(/^global-/,'') + arglist(args.map(&method(:compile_sexp)) + ["&"+compile_sexp(func)])
          else
            msg, *args = sexp

            msg.to_s.sub(/^global-/,'') + arglist(args.map(&method(:compile_sexp)))
          end
        else
          if sexp.include?(:&)
            raise "too many &'s" if sexp.count(:&) > 1
            raise "& found but not argument" if sexp.index(:&) == sexp.size-1
            posamp = sexp.index(:&)
            func = sexp[posamp+1]
            sexp = sexp.values_at(*(0..sexp.size-1).to_a - [posamp, posamp+1])
            msg, this, *args = sexp
            compile_sexp(this) + "." + msg.to_s +
              arglist(args.map(&method(:compile_sexp)) + ["&"+compile_sexp(func)])
          else
            msg, this, *args = sexp

            compile_sexp(this) + "." + msg.to_s +
              arglist(args.map(&method(:compile_sexp)))
          end
        end
      end
    else
      case sexp
      when Symbol
        sexp.to_s
      when Integer
        sexp.to_s
      when String
        sexp.inspect
      else
        raise "unknown data type #{sexp.inspect}"
      end
      # case sexp[:type]
      # when :symbol
      #   sexp[:value]
      #    # eval_symbol(sexp[:value])
      # # when :funcname
      # #   sexp[:value]
      # # when :number
      # #   sexp[:value] # numbers evaluate to themselves
      # # when :string
      # #   eval(sexp[:value], TOPLEVEL_BINDING)
      # else
      #   raise "unknown type of atom"
      # end
    end
  end

  def RubyLisp.macroexpand(sexp)
    if not sexp.is_a? Array
      sexp
    elsif sexp.empty?
      []
    # elsif sexp[0] == :when
    #   when_macro *sexp[1..-1]
    elsif $MACROS.has_key?(sexp[0])
      macro = $MACROS[sexp[0]]
      # p "calling macro #{macro} with #{sexp[1..-1].inspect}"
      macro.call(*sexp[1..-1])
    else
      [sexp[0]] + sexp[1..-1].map( &method(:macroexpand))
    end
  end

  def RubyLisp.when_macro(cond, *body)
    [:if, cond, [:progn, *body]]
  end

  def RubyLisp.symtok(str)
    {value: nil, type: str.to_sym}
  end

  def RubyLisp.read_from_string(str)
    toklist = tokenize(str.as String)
    code_as_data = parse(toklist)
  end

  def RubyLisp.tokenize string
    output = []
    loop do
      res = token(string)
      break if res == nil
      tok, string = res
#      STDERR.print "DEBUG: READ TOKEN: #{tok.inspect}\n"
      output << tok
    end
    # puts 
    output
  end

  def RubyLisp.token input
    case input 
    when ""
      nil
    when /\A\s+/
      token $'
    when /\A[()]/
      [symtok($&), $']
    when /\A&[a-zA-Z]+/
      [{value: $&, type: :symbol}, $']
    when /\A#'([@\$]?[a-z_][a-zA-Z_]*[?!]?)/
      [{value: $1.to_sym, type: :generic_function}, $']
    when /\A[%+\-*\/&=]+/
      [{value: $&, type: :symbol}, $']
    when /\A\.([A-Za-z_][a-zA-Z_]*[?!]?)/
      [{value: "global-" + $1, type: :symbol}, $']
    when /\A[@\$]?[A-Za-z_][a-zA-Z_]*[?!]?/
      [{value: $&, type: :symbol}, $']
    when /\A[0-9]+/
      [{value: $&.to_i, type: :number}, $']
    when /\A"[^"]*"/
      [{value: eval($&), type: :string}, $']
    else
      raise "scan error #{input.inspect}"
    end
  end


  def RubyLisp.parse_sexp tokens
    if tokens[0][:type] == :"("
      list = []
      tokens.shift
      until tokens[0][:type] == :")"
        sexp, tokens = parse_sexp tokens
        list << sexp
      end
      tokens.shift
      return [list, tokens]
    else
      atom = tokens.shift
      result = nil
      case atom[:type]
      when :symbol
        result = atom[:value].to_sym
      when :string
        result = atom[:value]
      when :number
        result = atom[:value]
      when :generic_function
        result = [:to_proc, [:quote, atom[:value].to_sym]]
      else
        raise "unkonwn atom type"
      end
      return [result, tokens]
    end
  end

  def RubyLisp.parse tokens
    output = []
    loop do
      sexp, tokens = parse_sexp(tokens)
      output << sexp
      break if tokens.empty?
    end
    output
  end
end  
  
