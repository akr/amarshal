module AMarshal
  class Next < Exception
  end

  def AMarshal.load(port)
    port = port.read if port.kind_of? IO
    eval port
  end

  def AMarshal.dump(obj, port='')
    vars = {}
    var = dump_sub obj, port, vars
    port << "#{var}\n"
  end

  def AMarshal.dump_sub(obj, port, vars)
    id = obj.__id__
    return vars[id] if vars.include? id

    if obj.respond_to? :am_name
      begin
	name = nil
	obj.am_nameinit(
	  lambda {|name| vars[id] = name},
	  lambda {|init_method, *init_args|
	    dump_call(port, name, init_method,
		      init_args.map {|arg| dump_sub(arg, port, vars)})
	  })
	return name
      rescue Next
      end
    end

    vars[id] = var = "v#{vars.size}"

    if obj.respond_to?(:am_literal) && obj.class.instance_methods.include?("am_literal")
      begin
	obj.am_litinit(
	  lambda {|lit| port << "#{var} = #{lit}\n"},
	  lambda {|init_method, *init_args|
	    dump_call(port, var, init_method,
		      init_args.map {|arg| dump_sub(arg, port, vars)})
	  })
	return var
      rescue Next
      end
    end

    if obj.respond_to? :am_allocinit
      obj.am_allocinit(
        lambda {|alloc_receiver, alloc_method, *alloc_args|
	  port << "#{var} = "
	  dump_call(port, dump_sub(alloc_receiver, port, vars), alloc_method,
		    alloc_args.map {|arg| dump_sub(arg, port, vars)})
	},
	lambda {|init_method, *init_args|
	  dump_call(port, var, init_method,
		    init_args.map {|arg| dump_sub(arg, port, vars)})
	})
      return var
    end

    raise ArgumentError.new("could not marshal #{obj.inspect}")
  end

  def AMarshal.dump_call(port, receiver, method, args)
    case method
    when :[]=
      port << "#{receiver}[#{args.first}] = #{args.last}\n"
    else
      port << "#{receiver}.#{method}(#{args.join ","})\n"
    end
  end
end

[IO, Binding, Continuation, Data, Dir, File::Stat, MatchData, Method, Proc, Thread, ThreadGroup].each {|c|
  c.class_eval {
    def am_allocinit(alloc_proc, init_proc)
      raise TypeError.new("can't dump #{self.class}")
    end
  }
}

class Object
  def am_nameinit(name_proc, init_proc)
    name_proc.call(am_name)
    am_init_instance_variables init_proc
  end

  def am_litinit(lit_proc, init_proc)
    lit_proc.call(am_literal)
    am_init_instance_variables init_proc
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
    self.each_with_index {|v, i| init_proc.call(:[]=, i, v)}
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
    super
    self.each {|k, v| init_proc.call(:[]=, k, v)}
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
    raise AMarshal::Next if /\A[A-Za-z_][0-9A-Za-z_]*\z/ !~ (str = to_s)
    ":" + str
  end

  def am_allocinit(alloc_proc, init_proc)
    alloc_proc.call(to_s, :intern)
    super(nil, init_proc)
  end
end

class Time
  def am_allocinit(alloc_proc, init_proc)
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
