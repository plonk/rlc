require 'optparse'
require_relative 'read.rb'

class CommandLineSyntaxError < StandardError
end

def main(args, options)
  LR.options = options

  if args.size > 1
    raise CommandLineSyntaxError, "Multiple files" 
  elsif args.size == 1
    LR.script(File.read(args[0]))
  else
    LR.repl
  end
end

def init
  options = {}
  opts = OptionParser.new
  opts.banner = "Usage: #{$0} [options] [script_file]"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = 1
  end
  opts.on("-q", "--no-init-file", "Suppress loading of builtin functions") do |v|
    options[:no_init_file] = true
  end
  opts.parse!
  main(ARGV, options)
rescue CommandLineSyntaxError => e
  puts e.message
  puts opts.help
end

init

