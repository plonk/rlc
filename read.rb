# -*- coding: utf-8 -*-
require_relative 'util.rb'
require_relative 'extension.rb'

$MACROS = {}

module LR
  MACRO_CHARS = {}

  def LR.builtin_stuff
    path = File.dirname(__FILE__) + "/builtin.lisp"
    File.read(path)
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
      # puts "read:"
      # p sexp
      ruby_code = compile_sexp macroexpand sexp
      # puts "ruby:"
      # puts ruby_code
      values << eval(ruby_code, env)
    end
    values.last
  end

  # Read Eval Print Loop
  def LR.repl()
    require 'readline'

    load_history
    env = TOPLEVEL_BINDING
    lisp_eval(builtin_stuff, env)
    while line = Readline.readline("> ", true)
      begin
        p lisp_eval(line + "\n", env)
      rescue PrematureEndException => e
        cont = Readline.readline("[#{e.message}] >> ", true)
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

  def LR.special_form?
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
    "def " + name.to_s + ' ' + LR.compile_lambda_list(lambda_list) + "; " + body.map(&method(:compile_sexp)).join('; ') + " end\n"
  end

  def LR.compile_defmacro(name, lambda_list, *body)
    "$MACROS[:#{name}] = " +
      "lambda { |#{compile_lambda_list(lambda_list)}| " +
      body.map(&method(:compile_sexp)).join("; ") + " }"
  end

  # sexp がリストなら関数呼出。
  # (map (quote ("abc" "def")) & (lambda (x) (upcase x)))
  # この関数はディスパッチだけするほうがいい。
  def LR.compile_sexp(sexp)
    if sexp.is_a? Array
      if sexp[0] == :quote
        sexp[1].inspect
      elsif sexp[0] == :private_function
        "method(#{sexp[1].inspect})"
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
      elsif sexp[0] == :"while"
        condition = compile_sexp(sexp[1])
        body = sexp[2..-1].map(&LR.method(:compile_sexp)).join("; ")
        "while #{condition} do #{body} end"
      elsif sexp[0] == :"return"
        _, value = sexp
        if b
          "return #{ compile_sexp(value) }"
        else
          "return"
        end
      elsif sexp[0] == :"break"
        _, value = sexp
        if value
          "break #{ compile_sexp(value) }"
        else
          "break"
        end
      else
        # この段階で sexp は [:msg, :receiver, :arg1, :arg2, ...] のよ
        # うになっている。
        #
        # 直後の引数がブロック引数であって、通常と異なる経路で渡さなけ
        # ればならないことを指示する & シンボルがあれば、そのようにする。
        if sexp[0].to_s =~ /^\./
          if sexp.include?(:&)
            raise "too many &'s" if sexp.count(:&) > 1
            raise "& found but not argument" if sexp.index(:&) == sexp.size-1
            posamp = sexp.index(:&)
            func = sexp[posamp+1]
            sexp = sexp.values_at(*(0..sexp.size-1).to_a - [posamp, posamp+1])
            msg, *args = sexp
            msg.to_s.sub(/^\./,'') + arglist(args.map(&method(:compile_sexp)) + ["&"+compile_sexp(func)])
          else
            msg, *args = sexp

            msg.to_s.sub(/^\./,'') + arglist(args.map(&method(:compile_sexp)))
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
                    [*'0'..'9']).join

  class PrematureEndException < StandardError
  end
  class NullInputException < StandardError
  end

  # String -> [Object, String]
  def LR.read input
    # 動いてるけど読めなさすぎる
    unless MACRO_CHARS.empty?
      if input =~ /\A([#{Regexp.escape(MACRO_CHARS.keys.join)}])/
        if MACRO_CHARS[$1].is_a? Proc
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
        raise PrematureEndException, "expecting )"
      end
      raise 'unreachable'
    when /\A[#{Regexp.escape ORDINARY_CHARS}]+/
      [$&.to_sym, $']
    when /\A\d+/
      [$&.to_i, $']
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

  MACRO_CHARS['#'] = {}

  set_macro_character(';', lambda { |input, char|
                        read(input.sub(/.*$/, ''))
                      })

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

end  
  
