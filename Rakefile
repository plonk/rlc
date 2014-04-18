load "config.rb"

task :default => ["rlci"]

SRC = %w[builtin.lisp extension.rb read.rb rlci.rb util.rb]

file 'rlci' => SRC do |task|
  sh "ruby rc.rb -o rlci rlci.rb"
  sh "echo __END__ >> rlci"
  sh "cat builtin.lisp >> rlci"
end

task :test do
  sh "rspec test-read.rb"
end

task :clean do
  sh "rm -f rlci"
end

task :install => ["rlci"] do
  sh "install rlci #{$BIN_DIR}"
  # sh "mkdir -p #{$RESOURCE_DIR}"
end

task :uninstall do
  sh "rm -v #{$BIN_DIR}/rlci"
  # sh "rm -rvf #{$RESOURCE_DIR}"
end
