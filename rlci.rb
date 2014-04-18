require 'optparse'
require_relative 'read.rb'

def main(args, options)
p options
  LR.options = options

  LR.repl
end

def init
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
      options[:verbose] = 1
    end
    opts.on("-q", "--no-init-file", "Suppress loading of builtin functions") do |v|
      options[:no_init_file] = true
    end
  end.parse!
  main(ARGV, options)
end

init

