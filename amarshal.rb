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
	name, *inits = obj.am_name_instance_variables
	vars[id] = name
	inits.each {|init_method, *init_args|
	  dump_call(port, name, init_method,
	            init_args.map {|arg| dump_sub(arg, port, vars)})
	}
	return name
      rescue Next
      end
    end

    vars[id] = var = "v#{vars.size}"

    if obj.respond_to? :am_literal
      begin
	lit, *inits = obj.am_literal_instance_variables
	port << "#{var} = #{lit}\n"
	inits.each {|init_method, *init_args|
	  dump_call(port, var, init_method,
	            init_args.map {|arg| dump_sub(arg, port, vars)})
	}
	return var
      rescue Next
      end
    end

    if obj.respond_to? :am_allocate_initialize
      (alloc_receiver, alloc_method, *alloc_args), *inits = obj.am_allocate_initialize
      port << "#{var} = "
      dump_call(port, dump_sub(alloc_receiver, port, vars), alloc_method,
		alloc_args.map {|arg| dump_sub(arg, port, vars)})
      inits.each {|init_method, *init_args|
	dump_call(port, var, init_method,
	          init_args.map {|arg| dump_sub(arg, port, vars)})
      }
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
    def am_allocate_initialize
      raise TypeError.new("can't dump #{self.class}")
    end
  }
}

class Object
  def am_name_instance_variables
    return [am_name, *am_instance_variable_inits]
  end

  def am_literal_instance_variables
    return [am_literal, *am_instance_variable_inits]
  end

  def am_allocate_initialize
    return [[self.class, :allocate], *am_instance_variable_inits]
  end

  def am_instance_variable_inits
    inits = []
    self.instance_variables.each {|iv|
      inits << [:instance_variable_set, iv, eval(iv)]
    }
    return inits
  end

  def instance_variable_set(var, val)
    eval "#{var} = val"
  end
end

class Array
  def am_allocate_initialize
    alloc, *inits = super
    self.each_with_index {|v, i| inits << [:[]=, i, v]}
    return [alloc, *inits]
  end
end

class Exception
  def am_allocate_initialize
    alloc, *inits = super
    inits << [:set_backtrace, backtrace] if backtrace
    return [[self.class, :new, message], *inits]
  end
end

class FalseClass
  alias am_name to_s
end

class Hash
  def am_allocate_initialize
    alloc, *inits = super
    self.each {|k, v| inits << [:[]=, k, v]}
    return [alloc, *inits]
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
  def am_literal
    str = '%.16g' % self
    str << ".0" if /\A[-+][0-9]*\z/ =~ str
    str
  end
end

class Range
  def am_allocate_initialize
    alloc, *inits = super
    inits << [:am_initialize, first, last, exclude_end?]
    return [alloc, *inits]
  end

  def am_initialize(first, last, exclude_end)
    initialize(first, last, exclude_end)
  end
end

class Regexp
  alias am_literal inspect
end

class String
  alias am_literal dump
end

class Struct
  def am_allocate_initialize
    alloc, *inits = super
    self.each_pair {|m, v| inits << [:[]=, m, v]}
    return [alloc, *inits]
  end
end

class Symbol
  def am_name
    raise AMarshal::Next if /\A[A-Za-z_][0-9A-Za-z_]*\z/ !~ (str = to_s)
    ":" + str
  end

  def am_allocate_initialize
    alloc, *inits = super
    return [[to_s, :intern], *inits]
  end
end

class Time
  def am_allocate_initialize
    alloc, *inits = super
    t = self.dup.utc
    alloc = [self.class, :utc, t.year, t.mon, t.day, t.hour, t.min, t.sec, t.usec]
    inits << [:localtime] unless utc?
    return [alloc, *inits]
  end
end

class TrueClass
  alias am_name to_s
end

class NilClass
  alias am_name inspect
end
