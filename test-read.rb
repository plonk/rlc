require_relative 'read.rb'

describe LR, 'compile_sexp' do
  it 'produces ruby code' do
    result = LR.compile_sexp([:a,:b])
    result.should eq("a(b)")
  end

  it 'produces ruby code' do
    result = LR.compile_sexp([:a,:b,:c])
    result.should eq("a(b, c)")
  end
end

describe LR, 'compile_lambda_list' do
  it 'produces ruby argument list' do
    result = LR.compile_lambda_list([:a, :b, :c])
    result.should eq("a, b, c")
  end

  it 'supports the rest arg' do
    result = LR.compile_lambda_list([:a, :"&rest", :b])
    result.should eq("a, *b")
  end
end

describe LR, 'compile_funcall' do 
  it 'hoge' do
    result = LR.compile_funcall([:"puts", "hoge"])
    result.should eq('puts("hoge")')
  end

  it 'hage' do
    result = LR.compile_funcall([[:meth, :to_s], 123])
    result.should eq('123.to_s()')
  end

  it 'fuga' do
    result = LR.compile_funcall([[:meth, :+], 1, 2])
    result.should eq('1.+(2)')
  end

  it 'foo' do 
    result = LR.compile_funcall([[:meth, :map], [:"list", 1,2,3], [:barg, [:lambda, [:x], :x]]])
    result.should eq('list(1, 2, 3).map(&lambda { |x| x })')
  end

  it 'baz' do
    result = LR.compile_argument_list([1])
    result.should eq('(1)')
  end
end

