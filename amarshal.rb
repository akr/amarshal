=begin
= AMarshal
== Methods
--- AMarshal.dump(obj[, port])
--- AMarshal.load(port)
=end

module AMarshal
  Next = :amarshal_try_next

  def AMarshal.load(port)
    port = port.read if port.kind_of? IO
    eval port
  end

  def AMarshal.dump(obj, port='')
    names = {}
    def names.next_index
      if defined? @next_index
	@next_index += 1
      else
	@next_index = 1
      end
      @next_index - 1
    end
    name = dump_rec obj, port, names
    port << "#{name}\n"
  end

  def AMarshal.dump_rec(obj, port, names)
    id = obj.__id__
    return names[id] if names.include? id

    name = nil
    init_proc = lambda {|init_method, *init_args|
		  dump_call(port, name, init_method,
			    init_args.map {|arg| dump_rec(arg, port, names)},
			    obj.private_methods.include?(init_method.to_s))
		}

    obj.am_nameinit(lambda {|name| names[id] = name}, init_proc) and
      return name

    next_index = names.next_index
    port << "v = []\n" if next_index == 0
    names[id] = name = "v[#{next_index}]"

    obj.am_litinit(lambda {|lit| port << "#{name} = #{lit}\n"}, init_proc) and
      return name

    obj.am_allocinit(lambda {|alloc_receiver, alloc_method, *alloc_args|
		       receiver = dump_rec(alloc_receiver, port, names)
		       args = alloc_args.map {|arg| dump_rec(arg, port, names)}
		       port << "#{name} = "
		       dump_call(port, receiver, alloc_method, args,
			 alloc_receiver.private_methods.include?(alloc_method.to_s))
		     }, init_proc)
    return name
  end

  def AMarshal.dump_call(port, receiver, method, args, private=false)
    if private
      port << "#{receiver}.__send__(:#{method}#{args.map {|arg| ", #{arg}"}})\n"
    else
      case method
      when :[]=
	port << "#{receiver}[#{args[0]}] = #{args[1]}\n"
      when :<<
	port << "#{receiver} << #{args[0]}\n"
      else
	if /\A([A-Za-z_][0-9A-Za-z_]*)=\z/ =~ method.to_s
	  port << "#{receiver}.#{$1} = #{args[0]}\n"
	else
	  port << "#{receiver}.#{method}(#{args.map {|arg| arg.to_s}.join ","})\n"
	end
      end
    end
  end
end

[IO, Binding, Continuation, Data, Dir, File::Stat, MatchData, Method, Proc, Thread, ThreadGroup].each {|c|
  c.class_eval {
    def am_allocinit(alloc_proc, init_proc)
      raise ArgumentError.new("can't dump #{self.class}")
    end
  }
}

class Object
  def method_defined_at?(name, mod)
    name = name.to_s
    mod = mod.to_s

    meth = method(name)
    s = meth.inspect

    raise "method inspection doesn't begin with \"#<\"" if /\A#</ !~ s
    s = $'
    raise "method inspection has unexpected method class name" if /\A#{Regexp.quote meth.class.to_s}/ !~ s
    s = $'
    raise "method inspection doesn't separated properly" if /\A: / !~ s
    s = $'

    raise "method inspection doesn't end with ">"" unless s.chomp! '>'
    raise "method inspection has unexpected method name" unless /([.#])#{Regexp.quote name}\z/ =~ s
    s = $`
    mark = $1

    if mark == '.'
      s2 = self.inspect
      raise "singleton method inspection has unexpected receiver inspection" unless /\A#{Regexp.quote s2}/ =~ s
      unless $'.empty?
	s = $'
	raise "defining class of singleton method inspection doesn't end with \")\"" unless s.chomp! ')'
	raise "defining class of singleton method inspection doesn't begin with \"(\"" unless /\A\(/ =~ s
	s = $'
      end
      s == mod
    else
      raise "method inspection has unexpected receiver class" unless /\A#{Regexp.quote self.class.to_s}/ =~ s
      unless $'.empty?
	s = $'
	raise "defining class of method inspection doesn't end with \")\"" unless s.chomp! ')'
	raise "defining class of method inspection doesn't begin with \"(\"" unless /\A\(/ =~ s
	s = $'
      end
      s == mod
    end
  end

  def am_nameinit(name_proc, init_proc)
    respond_to?(:am_name) and
    catch(AMarshal::Next) {
      name_proc.call(am_name)
      #am_init_instance_variables init_proc
      return true
    }
    return false
  end

  def am_litinit(lit_proc, init_proc)
    respond_to?(:am_literal) and
    self.class.instance_methods.include?("am_literal") and
    catch(AMarshal::Next) {
      lit_proc.call(am_literal)
      am_init_instance_variables init_proc
      am_init_extentions init_proc
      return true
    }
    return false
  end

  def am_allocinit(alloc_proc, init_proc)
    alloc_proc.call(self.class, :allocate) if alloc_proc
    am_init_instance_variables init_proc
    am_init_extentions init_proc
  end

  def am_init_instance_variables(init_proc)
    self.instance_variables.each {|iv|
      init_proc.call(:instance_variable_set, iv, eval(iv))
    }
  end

  def instance_variable_set(var, val)
    eval "#{var} = val"
  end

  def am_singleton?
    return true unless self.singleton_methods.empty?
    singleton_class = class << self
      self
    end
    return true unless singleton_class.instance_variables.empty?
    not (singleton_class.ancestors - self.class.ancestors).empty?
  end

  def am_init_extentions(init_proc)
    unless self.singleton_methods.empty?
      raise TypeError.new("singleton can't be dumped")
    end
    singleton_class = class << self
      unless instance_variables.empty?
	raise TypeError.new("singleton can't be dumped")
      end
      self
    end
    (singleton_class.ancestors - self.class.ancestors).reverse_each {|m|
      init_proc.call(:extend, m)
    }
  end
end

class Array
  def am_allocinit(alloc_proc, init_proc)
    super
    self.each_with_index {|v, i| init_proc.call(:<<, v)}
  end
end

class Exception
  def am_allocinit(alloc_proc, init_proc)
    super
    init_proc.call(:am_initialize, message)
    init_proc.call(:set_backtrace, backtrace) if backtrace
  end
  alias am_initialize initialize
end

class FalseClass
  alias am_name to_s

  def am_init_extentions(init_proc)
  end
end

class Hash
  def am_allocinit(alloc_proc, init_proc)
    raise ArgumentError.new("can't dump #{self.class} with default proc") if self.default_proc
    super
    self.each {|k, v| init_proc.call(:[]=, k, v)}
    init_proc.call(:default=, self.default) if self.default != nil
  end
end

class Module
  def am_name
    n = name
    raise ArgumentError.new("can't dump anonymous class #{self.inspect}") if /\A#/ =~ n
    n
  end
end

class Bignum
  alias am_literal to_s
end

class Fixnum
  alias am_name to_s

  def am_init_extentions(init_proc)
  end
end

class Float
  # Float.am_nan, Float.am_pos_inf and Float.am_neg_inf are not a literal.
  def am_literal
    if self.nan?
      "Float.am_nan"
    elsif self.infinite?
      if 0 < self
	"Float.am_pos_inf"
      else
	"Float.am_neg_inf"
      end
    elsif self == 0.0
      if 1.0 / self < 0
        "-0.0"
      else
        "0.0"
      end
    else
      str = '%.16g' % self
      str << ".0" if /\A-?[0-9]+\z/ =~ str
      str
    end
  end

  def Float.am_nan() 0.0 / 0.0 end
  def Float.am_pos_inf() 1.0 / 0.0 end
  def Float.am_neg_inf() -1.0 / 0.0 end
end

class Range
  def am_allocinit(alloc_proc, init_proc)
    super
    if self.method_defined_at?(:initialize, Range)
      init = :initialize
    else
      init = :am_initialize
    end
    init_proc.call(init, first, last, exclude_end?)
  end
  alias am_initialize initialize
end

class Regexp
  alias am_literal inspect

  def am_allocinit(alloc_proc, init_proc)
    super
    if self.method_defined_at?(:initialize, Regexp)
      init = :initialize
    else
      init = :am_initialize
    end
    init_proc.call(init, self.source, self.options)
  end
  alias am_initialize initialize
end

class String
  alias am_literal dump

  def am_allocinit(alloc_proc, init_proc)
    super
    if self.method_defined_at?(:initialize, String)
      init = :initialize
    else
      init = :am_initialize
    end
    init_proc.call(init, String.new(self))
  end
  alias am_initialize initialize
end

class Struct
  def am_allocinit(alloc_proc, init_proc)
    super
    self.each_pair {|m, v| init_proc.call(:[]=, m, v)}
  end
end

class Symbol
  def am_name
    throw AMarshal::Next if %r{\A(?:[A-Za-z_][0-9A-Za-z_]*[?!=]?|\||\^|&|<=>|==|===|=~|>|>=|<|<=|<<|>>|\+|\-|\*|/|%|\*\*|~|\+@|\-@|\[\]|\[\]=|\`)\z} !~ (str = to_s)
    ":" + str
  end

  def am_allocinit(alloc_proc, init_proc)
    alloc_proc.call(to_s, :intern)
    super(nil, init_proc)
  end

  def am_init_extentions(init_proc)
  end
end

class Time
  def am_allocinit(alloc_proc, init_proc)
    if self.class.method_defined_at?(:utc, Time)
      utc_method = :utc
    else
      utc_method = :am_utc
    end
    t = self.dup.utc
    alloc_proc.call(self.class, utc_method, t.year, t.mon, t.day, t.hour, t.min, t.sec, t.usec)
    super(nil, init_proc)
    init_proc.call(:localtime) unless utc?
  end

  class << Time
    alias am_utc utc
  end
end

class TrueClass
  alias am_name to_s

  def am_init_extentions(init_proc)
  end
end

class NilClass
  alias am_name inspect

  def am_init_extentions(init_proc)
  end
end
