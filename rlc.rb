# ruby lisp compiler

require_relative 'read.rb'

str = File.read(ARGV[0])
until str.empty?
  sexp, str = RubyLisp.read(str)
  puts RubyLisp.compile_sexp(sexp)
end
  
