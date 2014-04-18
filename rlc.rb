# ruby lisp compiler

require_relative 'read.rb'

str = RubyLisp.builtin_stuff
until str =~ /\A\s*\z/
  sexp, str = RubyLisp.read str 
  puts RubyLisp.compile_sexp(sexp)
end

str = File.read(ARGV[0])
until str =~ /\A\s*\z/
  sexp, str = RubyLisp.read(str)
  puts RubyLisp.compile_sexp(sexp)
end
  
