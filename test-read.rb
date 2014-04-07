require_relative 'read.rb'

describe RubyLisp, "token" do
  it "reads a symbol" do
    result = RubyLisp.token("a")
    result.should eq([{value:'a', type: :symbol}, ''])
  end

  it "reads a list" do
    tok, rest = RubyLisp.token("()")
    tok.should eq({value: nil, type: :"("})
    rest.should eq(')')
  end

end

describe RubyLisp, 'tokenize' do
  it "reads an S-expression" do
    result = RubyLisp.tokenize("(a b)")
    result.should eq([
                      {value: nil, type: :"("},
                      {value: "a", type: :symbol},
                      {value: "b", type: :symbol},
                      {value: nil, type: :")"}
                     ])
  end
end

describe RubyLisp, 'parse' do
  it 'converts tokenlist to a Ruby object' do
    result = RubyLisp.parse(RubyLisp.tokenize("(a b)"))
    result.should eq([[:a, :b]])
  end
end

describe RubyLisp, 'read_from_string' do
  it 'reads a string and converts it to a ruby object' do
    result = RubyLisp.read_from_string("(a b)")
    result.should eq([[:a, :b]])
  end
end

describe RubyLisp, 'compile_sexp' do
  it 'produces ruby code' do
    result = RubyLisp.compile_sexp([:a,:b])
    result.should eq("b.a")
  end

  it 'produces ruby code' do
    result = RubyLisp.compile_sexp([:a,:b,:c])
    result.should eq("b.a(c)")
  end
end

describe RubyLisp, 'compile_lambda_list' do
  it 'produces ruby argument list' do
    result = RubyLisp.compile_lambda_list([:a, :b, :c])
    result.should eq("a, b, c")
  end

  it 'supports the rest arg' do
    result = RubyLisp.compile_lambda_list([:a, :"&rest", :b])
    result.should eq("a, *b")
  end
end
    
