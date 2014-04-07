# ruby lisp compiler

require_relative 'read.rb'

puts RubyLisp.compile(RubyLisp.read_from_string(File.read("fizz.lisp")))
