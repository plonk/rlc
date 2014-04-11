# -*- coding: utf-8 -*-
require_relative 'util.rb'
require_relative 'extension.rb'

$MACROS = {}

module LR
  MACRO_CHARS = {}

  BUILTIN_STUFF = File.dirname(__FILE__) + "/builtin.lisp"

  def LR.read_body(str)
    values = []
    loop do
      begin
        sexp, str = read(str)
      rescue NullInputException
        if values.nonempty?
          return values
        else
          raise
        end
      end
      values << macroexpand(sexp)
    end
    values
  end

  def LR.lisp_eval(str, env)
    values = []
    until str.empty?
      begin
        sexp, str = read(str)
      rescue NullInputException
        if values.nonempty?
          return values.last
        else
          raise
        end
      end
      if verbose
        puts "read:"
        p sexp
      end
      ruby_code = compile_sexp macroexpand sexp
      if verbose
        puts
        puts "ruby:"
        puts ruby_code
      end
      puts
      values << eval(ruby_code, env)
    end
    values.last
  end

  def LR.load pathname
    begin
      src = File.read(pathname)
      lisp_eval(src.gsub(/\n/m, ' ').strip, TOPLEVEL_BINDING)
    rescue PrematureEndException => e
      raise
    end
  end

  def LR.load_builtin
    str = File.read( BUILTIN_STUFF ).strip
    while str.nonempty?
      sexp, str = LR.read(str)
      sexp = macroexpand sexp
      eval(compile_sexp(sexp), TOPLEVEL_BINDING)
    end
  end

  # Read Eval Print Loop
  def LR.repl()
    require 'readline'

    load_history
    env = TOPLEVEL_BINDING
    LR.load_builtin unless options[:no_init_file]
    while line = Readline.readline("> ", true)
      begin
        p lisp_eval(line + "\n", env)
      rescue NullInputException => e
        next
      rescue PrematureEndException => e
        cont = Readline.readline("#{e.message}> ", true)
        if cont
          line += "\n" + cont
          retry
        else
          puts "\nCancelled.\n"
        end
      # rescue NullInputException => e
      rescue StandardError => e
        puts $!
        puts $@
      end
    end
  ensure
    save_history
  end

  HISTORY_FILE = ENV['HOME'] + "/.lor_history"
  HISTORY_LINES = 3000

  def LR.load_history
    File.open(HISTORY_FILE, "r") do |his|
      his.read.each_line.each do |line|
        Readline::HISTORY << line.chomp
      end
    end
  rescue StandardError => e
    STDERR.puts "Could not load #{HISTORY_FILE}. #{e}"
  end

  def  LR.save_history
    File.open(HISTORY_FILE, "w") do |his|
      Readline::HISTORY.to_a
        .reverse.uniq.reverse	# 新しい項目を残して重複削除
        .reject(&:empty?)	# 空行削除
        .take(HISTORY_LINES)
        .map(&:terpri).join
        .apply(&his.method(:print))
    end
  end

  def LR.compile(ls)
    ls.map { |sexp| compile_sexp(sexp) }.join("\n")
  end

  def LR.special_form? sym
    SPECIAL_FORMS.has_key? sym.as(Symbol)
  end

  def LR.compile_lambda_list(ls)
    if (i = ls.index(:"&rest")) != nil
      ls.delete(:"&rest")
    end
    result = ls.map do |item|
      if item.is_a? Array
        "(#{compile_lambda_list(item)})"
      else
        item.to_s
      end
    end
    if i
      result[i] = "*" + result[i]
    end
    result.join(', ')
  end

  def LR.arglist(list)
    if list.empty?
      ""
    else
      "(" + list.join(', ') + ")"
    end
  end

  def LR.compile_def(name, lambda_list, *body)
    if function_name? name
      "def " + name.to_s + ' ' + LR.compile_lambda_list(lambda_list) + "; " + body.map(&method(:compile_sexp)).join('; ') + " end\n"
    else
      "define_method #{name.inspect} do |#{LR.compile_lambda_list(lambda_list)}| #{body.map(&method(:compile_sexp)).join('; ')} end\n"
    end
  end

  def LR.compile_defmacro(name, lambda_list, *body)
    "$MACROS[:#{name}] = " +
      "lambda { |#{compile_lambda_list(lambda_list)}| " +
      body.map(&method(:compile_sexp)).join("; ") + " }"
  end

  SPECIAL_FORMS = {
    quote: lambda { |obj| obj.inspect },

    barg: lambda { |sexp|
      "&#{compile_sexp sexp}" },

    function: lambda { |obj|
      if obj.list? and obj[0].any_of?(:lambda, :proc, :meth)
        compile_sexp(obj)
      elsif obj.symbol?
        "method(#{obj.inspect})"
      else
        raise "#{obj.inspect} is not a function name"
      end },

    meth: lambda { |sym|
      "#{sym.inspect}.to_proc" },

    setq: lambda { |var, val| "#{var} = #{compile_sexp(val)}" },
    :"if" => lambda { |condition, thenclause, elseclause|
      "if #{compile_sexp(condition)} then #{compile_sexp(thenclause)}" +
      if elseclause
      then " else #{compile_sexp(elseclause)} end"
      else " end" end },

    progn: lambda { |*body|
      '(' + body.map(&method(:compile_sexp)).join('; ') + ')' },

    :"lambda" => lambda { |lambda_list, *rest|
      args = compile_lambda_list(lambda_list) 
      "lambda { |#{args}| #{rest.map{|x| compile_sexp(x)}.join('; ')} }" },

    :"proc" => lambda { |lambda_list, *rest|
      args = compile_lambda_list(lambda_list) 
      "proc { |#{args}| #{rest.map{|x| compile_sexp(x)}.join('; ')} }" },

    :def => method(:compile_def),

    defmacro: method(:compile_defmacro),

    :"while" => lambda { |condition, *body|
      body = body.map(&method(:compile_sexp)).join("; ")
      "while #{condition} do #{body} end" },

    :"return" => lambda { |value|
      if b
        "return #{ compile_sexp(value) }"
      else
        "return"
      end },

    :"break" => lambda { |value|
      if value
        "break #{ compile_sexp(value) }"
      else
        "break"
      end },
  }

  def LR.function_name?(symbol)
    (symbol.as(Symbol).to_s =~ /\A[A-Za-z_]+[!?]?\z/) ? true : false
  end

  def LR.compile_methodcall(msg, this, args)
    "#{compile_sexp(this)}.#{msg.to_s}#{args}"
  end

  def LR.compile_argument_list ls
    ls.map { |arg|
      if arg.list? and arg[0] == :barg
        "&"+compile_sexp(arg[1])
      else
        compile_sexp(arg)
      end
    }.join(", ").apply { |inner| "(" + inner + ")" }
  end

  def LR.compile_funcall(sexp)
    # この段階で sexp は [:fn, :receiver, :arg1, :arg2, ...] のよ
    # うになっている。
    #
    # 直後の引数がブロック引数であって、通常と異なる経路で渡さなけ
    # ればならないことを指示する & シンボルがあれば、そのようにする。
    fn, *args = sexp

    if fn.list? and fn[0].any_of?(:lambda, :proc, :meth)
      case fn[0]
      when :lambda
        lam = compile_sexp fn
        lam + ".call" + compile_argument_list(args)
      when :proc
        lam = compile_sexp fn
        lam + ".call" + compile_argument_list(args)
      when :meth
        receiver, *args = args
        arglist = compile_argument_list(args)
        compile_methodcall(fn[1], receiver, arglist)
      end
    elsif fn.is_a? Symbol
      if function_name?(fn)
        fn.to_s + compile_argument_list(args)
      else
        "self.send" + compile_argument_list([fn.inspect] + args)
      end
    else
      raise "#{fn} is not a function name"
    end
  end

  # sexp がリストなら関数呼出。
  # (map (quote ("abc" "def")) & (lambda (x) (upcase x)))
  # この関数はディスパッチだけするほうがいい。
  def LR.compile_sexp(sexp)
    if sexp.list?
      if SPECIAL_FORMS.has_key? sexp.first
        SPECIAL_FORMS[sexp.first].call(*sexp.rest)
      else
        compile_funcall(sexp)
      end
    else
      case sexp
      when Symbol
        sexp.to_s
      when Integer
        sexp.to_s
      when String
        sexp.inspect
      when Regexp
        "#{sexp.inspect}"
      else
        raise "unknown data type #{sexp.class.inspect}"
      end
    end
  end

  def LR.macroexpand(sexp)
    if not sexp.is_a? Array # if atom
      sexp
    elsif sexp.empty?
      []
    # elsif sexp[0] == :when
    #   when_macro *sexp[1..-1]
    elsif $MACROS.has_key?(sexp[0])
      macro = $MACROS[sexp[0]]
      # p "calling macro #{macro} with #{sexp[1..-1].inspect}"
      LR.macroexpand macro.call(*sexp[1..-1])
    else
      [sexp[0]] + sexp[1..-1].map( &method(:macroexpand))
    end
  end

  def LR.when_macro(cond, *body)
    [:if, cond, [:progn, *body]]
  end

  def LR.symtok(str)
    {value: nil, type: str.to_sym}
  end

  class CloseParenException < StandardError
    attr_reader :rest
    def initialize(rest)
      @rest = rest
    end
  end

  ORDINARY_CHARS = ((32..126).map(&:chr) -
                    [" ", ?#, ?(, ?), ?', ?", ?;, ?/] -
                    # ['.'] -
                    # [*'0'..'9']
                    []).join

  class PrematureEndException < StandardError
    attr_reader :rest

    def initialize(msg, rest)
      super(msg)
      @rest = rest
    end
  end

  class NullInputException < StandardError
  end

  def LR.read input
    # puts "read: #{input[0..10].inspect} goes in"
    LR._read(input).tap { |out|
      # puts "read: #{out.inspect} goes out"
    }
  end

  # String -> [Object, String]
  def LR._read input
    # 動いてるけど読めなさすぎる
    unless MACRO_CHARS.empty?
      if input =~ /\A([#{Regexp.escape(MACRO_CHARS.keys.join)}])/
        if MACRO_CHARS[$1].respond_to? :call
          return MACRO_CHARS[$1].call($', $1)
        elsif MACRO_CHARS[$1].is_a? Hash
          ftable = MACRO_CHARS[$1]
          if fn = ftable[$'[0]]
            return fn.call($'[1..-1], $1, $'[0])
          else
            raise "no dispatch macro for #{$1} #{$'[0]}"
          end
        else
          raise "something wrong"
        end
      end
    end

    case input
    when ''
      raise NullInputException, 'null input'
    when /\A\s+/
      read $'
    when /\A\)/
      raise CloseParenException.new($')
    when /\A\(/
      begin
        str = $'
        result = []
        loop do
          sexp, str = read(str)
          result << sexp
        end
      rescue CloseParenException => e
        return [result, e.rest]
      rescue NullInputException => e
        raise PrematureEndException.new("expecting )", str)
      end
      raise 'unreachable'
    when /\A\d+/
      [$&.to_i, $']
    when /\A[#{Regexp.escape ORDINARY_CHARS}]+/
      [$&.to_sym, $']
    when /\A"/
      rest = $'
      if ( match = rest.match(/\A[^"]*"/) ) != nil
        str = match.to_s[0..-2]
      else
        raise PrematureEndException, 'could not find balancing double quote'
        # raise 'could not find balancing double quote'
      end
      [str, $']
    else
      raise "parse error #{input.inspect}"
    end
  end

  def LR.parse tokens
    output = []
    loop do
      sexp, tokens = parse_sexp(tokens)
      output << sexp
      break if tokens.empty?
    end
    output
  end

  def LR.set_macro_character char, fn
    MACRO_CHARS[char] = fn
  end

  def LR.set_dispatch_macro_character char1, char2, fn
    MACRO_CHARS[char1] ||= char1
    MACRO_CHARS[char1][char2] = fn
  end

  def LR.verbose
    @options[:verbose]
  end

  def LR.verbose=(val)
    @options[:verbose]=val
  end

  def LR.options
    @options
  end

  def LR.options= hash
    @options = hash.as({Symbol=>Object})
  end

  MACRO_CHARS['#'] = {}

  # コメント記法
  set_macro_character(';', lambda { |input, char|
                        read(input.sub(/.*$/, ''))
                      })

  # 正規表現リテラル
  set_macro_character('/', lambda { |input, char|
                        input = input.dup
                        buf = ""
                        while (char = input.shift) != '/'
                          if char == nil
                            raise PrematureEndException, "no balancing /"
                          elsif char == '\\' and ['/','\\'].include? input.first
                            buf << input.shift
                          else
                            buf << char
                          end
                        end
                        [Regexp.new(buf), input]
                      })

  # インスタンスメソッド記法
  set_macro_character('.', lambda { |input, char|
                        msg, rest = read(input)
                        exp = [:meth, msg]
                        [exp, rest]
                      })

  # ブロック引数記法
  set_dispatch_macro_character('#', '&',
                               lambda { |input, char1, char2|
                                 sexp, rest = read(input)
                                 [
                                  [:barg, [:function, sexp]], rest]
                               })

  # S-exp コメント
  set_dispatch_macro_character('#', '/',
                               lambda { |input, char1, char2|
                                 sexp, rest = read(input)
                                 read(rest)
                               })

end  

def message_apply(receiver, msg, args, &blk)
  # p [:message_apply, receiver, msg, args, blk]
  receiver.send(msg, *args, &blk)
end

# def block(&blk)
#   blk
# end
