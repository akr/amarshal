=begin
= AMarshal
== Methods
--- AMarshal.dump(obj[, port])
--- AMarshal.load(port)
=end

module AMarshal
  class Next < Exception
  end

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
			    init_args.map {|arg| dump_rec(arg, port, names)})
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
		       dump_call(port, receiver, alloc_method, args)
		     }, init_proc)
    return name
  end

  def AMarshal.dump_call(port, receiver, method, args)
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

[IO, Binding, Continuation, Data, Dir, File::Stat, MatchData, Method, Proc, Thread, ThreadGroup].each {|c|
  c.class_eval {
    def am_allocinit(alloc_proc, init_proc)
      raise ArgumentError.new("can't dump #{self.class}")
    end
  }
}

class Object
  def am_nameinit(name_proc, init_proc)
    respond_to?(:am_name) and
    begin
      name_proc.call(am_name)
      #am_init_instance_variables init_proc
      return true
    rescue AMarshal::Next
    end
    return false
  end

  def am_litinit(lit_proc, init_proc)
    respond_to?(:am_literal) and
    self.class.instance_methods.include?("am_literal") and
    begin
      lit_proc.call(am_literal)
      am_init_instance_variables init_proc
      return true
    rescue AMarshal::Next
    end
    return false
  end

  def am_allocinit(alloc_proc, init_proc)
    alloc_proc.call(self.class, :allocate) if alloc_proc
    am_init_instance_variables init_proc
  end

  def am_init_instance_variables(init_proc)
    self.instance_variables.each {|iv|
      init_proc.call(:instance_variable_set, iv, eval(iv))
    }
  end

  def instance_variable_set(var, val)
    eval "#{var} = val"
  end

  def am_initialize(*args)
    am_orig_initialize(*args)
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
  alias am_orig_initialize initialize
end

class FalseClass
  alias am_name to_s
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
    raise ArgumentError.new("can't dump anonymous class #{self.inspect}") if n.empty?
    n
  end
end

class Bignum
  alias am_literal to_s
end

class Fixnum
  alias am_name to_s
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
    init_proc.call(:am_initialize, first, last, exclude_end?)
  end
  alias am_orig_initialize initialize
end

class Regexp
  alias am_literal inspect

  def am_allocinit(alloc_proc, init_proc)
    super
    init_proc.call(:am_initialize, self.source, self.options)
  end
  alias am_orig_initialize initialize
end

class String
  alias am_literal dump

  def am_allocinit(alloc_proc, init_proc)
    super
    init_proc.call(:am_initialize, String.new(self))
  end
  alias am_orig_initialize initialize
end

class Struct
  def am_allocinit(alloc_proc, init_proc)
    super
    self.each_pair {|m, v| init_proc.call(:[]=, m, v)}
  end
end

class Symbol
  def am_name
    raise AMarshal::Next if %r{\A(?:[A-Za-z_][0-9A-Za-z_]*[?!=]?|\||\^|&|<=>|==|===|=~|>|>=|<|<=|<<|>>|\+|\-|\*|/|%|\*\*|~|\+@|\-@|\[\]|\[\]=|\`)\z} !~ (str = to_s)
    ":" + str
  end

  def am_allocinit(alloc_proc, init_proc)
    alloc_proc.call(to_s, :intern)
    super(nil, init_proc)
  end
end

class Time
  def am_allocinit(alloc_proc, init_proc)
    # should use X.utc if X.utc is not redefined.
    t = self.dup.utc
    alloc_proc.call(self.class, :am_utc, t.year, t.mon, t.day, t.hour, t.min, t.sec, t.usec)
    super(nil, init_proc)
    init_proc.call(:localtime) unless utc?
  end

  class << Time
    alias am_utc utc
  end
end

class TrueClass
  alias am_name to_s
end

class NilClass
  alias am_name inspect
end
