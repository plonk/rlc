class String
  # Terminate Print Line
  def terpri
    if self =~ /\n\z/
      self
    else
      self + "\n"
    end
  end

  def first
    self[0]
  end

  def shift
    self.first.tap { self.sub!(/\A./m,'') }
  end

  def unshift char
    self.sub!(/\A/, char)
  end
end

class Object
  def any_of? *things
    things.include? self
  end

  def symbol?
    false
  end

  def apply(*more_args, &f)
    f.call(self, *more_args)
  end

  def recur(*more_args, &blk)
    f = lambda { |*args| blk.(f, *args) }
    blk.(f, self, *more_args)
  end

  def list?
    false
  end

  def nonempty?
    not empty?
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

  def list?
    true
  end

  def remove_at(*indices)
    self.reject.with_index { |e, i| indices.include? i }
  end
end

class Symbol
  def symbol?
    true
  end

  def [] obj
    obj.method self
  end

  def undot
    self.to_s.sub(/^\./,'').to_sym
  end
end
