# -*- coding: utf-8 -*-
require_relative 'util.rb'

class String
  # Terminate Print Line
  def terpri
    if self =~ /\n\z/
      self
    else
      self + "\n"
    end
  end
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

class Symbol
  def [] obj
    obj.method self
  end
end

$MACROS = {}

module RubyLisp
  MACRO_CHARS = {}

  def RubyLisp.builtin_stuff
    path = File.dirname(__FILE__) + "/builtin.lisp"
    File.read(path)
  end

  def RubyLisp.lisp_eval(str, env)
    until str =~ /\A\s*\z/
      sexp, str = read(str)
      puts "read:"
      p sexp
      ruby_code = compile_sexp macroexpand sexp
      puts "ruby:"
      puts ruby_code
      eval ruby_code, env
    end
  end

  # Read Eval Print Loop
  def RubyLisp.repl()
    require 'readline'

    load_history
    env = TOPLEVEL_BINDING
    lisp_eval(builtin_stuff, env)
    while line = Readline.readline("> ", true)
      begin
        until line =~ /\A\s*\z/
          sexp, line = read(line)

          puts "read:\n\t#{sexp.inspect}"

          
          ruby_code = compile_sexp sexp.apply &:macroexpand[RubyLisp]

          puts "ruby code:\n\t#{ruby_code}"

          result = eval(ruby_code, env)

          puts
          p result
        end
      rescue PrematureSexpEnd => e
        cont = Readline.readline(">> ", true)
        if cont
          line += " " + cont
          retry
        else
          puts "\nCancelled.\n"
        end
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

  def RubyLisp.load_history
    File.open(HISTORY_FILE, "r") do |his|
      his.read.each_line.each do |line|
        Readline::HISTORY << line.chomp
      end
    end
  rescue StandardError => e
    STDERR.puts "Could not load #{HISTORY_FILE}. #{e}"
  end

  def  RubyLisp.save_history
    File.open(HISTORY_FILE, "w") do |his|
      Readline::HISTORY.to_a
        .reverse.uniq.reverse	# 新しい項目を残して重複削除
        .reject(&:empty?)	# 空行削除
        .take(HISTORY_LINES)
        .map(&:terpri).join
        .apply(&his.method(:print))
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
        body = sexp[2..-1].map(&RubyLisp.method(:compile_sexp)).join("; ")
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
    if not sexp.is_a? Array # if atom
      sexp
    elsif sexp.empty?
      []
    # elsif sexp[0] == :when
    #   when_macro *sexp[1..-1]
    elsif $MACROS.has_key?(sexp[0])
      macro = $MACROS[sexp[0]]
      # p "calling macro #{macro} with #{sexp[1..-1].inspect}"
      RubyLisp.macroexpand macro.call(*sexp[1..-1])
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

  class CloseParenException < StandardError
    attr_reader :rest
    def initialize(rest)
      @rest = rest
    end
  end

  ORDINARY_CHARS = ((32..126).map(&:chr) -
                    [" ", ?#, ?(, ?), ?', ?", ?;] -
                    # ['.'] -
                    [*'0'..'9']).join

  class PrematureSexpEnd < StandardError
  end

  # String -> [Object, String]
  def RubyLisp.read input
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
      raise PrematureSexpEnd, 'null input'
    when /\A;[^\n]+\n/
      read $'
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
        raise 'could not find balancing double quote'
      end
      [str, $']
    else
      raise "parse error #{input.inspect}"
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

  def RubyLisp.set_macro_character char, fn
    MACRO_CHARS[char] = fn
  end

  def RubyLisp.set_dispatch_macro_character char1, char2, fn
    MACRO_CHARS[char1] ||= char1
    MACRO_CHARS[char1][char2] = fn
  end

  MACRO_CHARS['#'] = {}
end  
  
