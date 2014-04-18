# ruby to lisp compiler

require_relative 'read.rb'

str = File.read LR::BUILTIN_STUFF
until str =~ /\A\s*\z/
  sexp, str = LR.read str 
  puts LR.compile_sexp(sexp)
end

str = File.read(ARGV[0])
until str =~ /\A\s*\z/
  sexp, str = LR.read(str)
  puts LR.compile_sexp(sexp)
end
