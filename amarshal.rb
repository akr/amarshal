class AMarshal
  def AMarshal.load(port)
    port = port.read if port.kind_of? IO
    eval port
  end

  def AMarshal.dump(obj, port='')
    am = AMarshal.new(obj, port)
    am.print "#{am.put1(obj)}\n"
    port
  end

  def put(obj)
    traverse(obj) {|state|
      put1(obj) if state == :tree
    }
    return @name[obj.__id__]
  end

  def put1(obj)
    prefix = obj.class.name.gsub(/[^a-zA-Z]/, '').downcase
    prefix = 'obj' if prefix == ''
    @name[obj.__id__] = "#{prefix}#{obj.__id__}"
    obj.am_dump(self) {|name| @name[obj.__id__] = name if name; @name[obj.__id__]}
    return @name[obj.__id__]
  end

  def put_instance_variables(obj, name)
    obj.instance_variables.each {|var|
      value = obj.instance_eval var
      self.print "#{name}.instance_eval {#{var} = #{self.put(value)}}\n"
    }
  end

  def print(*args)
    args.each {|v| @port << v}
  end

  def initialize(obj, port)
    @curr = @number = 1
    @hash = {obj.__id__ => -1}
    @port = port
    @name = {}
  end

  def status(obj)
    id = obj.__id__
    unless @hash.include? id
      return :tree
    end

    number = @hash[id]
    if number < 0
      return :backward
    elsif @curr < number
      return :forward
    else
      return :cross
    end
  end

  def traverse(obj)
    if (s = status(obj)) == :tree
      id = obj.__id__
      number = @number += 1
      @hash[id] = -number
      prev = @curr
      @curr = number
      yield s
      @curr = prev
      @hash[id] = number
    else
      yield s
    end
  end

end

class MarshalStringWriter
  def initialize(out='', major=4, minor=6)
    @out = out
    byte major
    byte minor
  end

  attr_reader :out

  def byte(d)
    @out << [d].pack('C')
  end

  def long(d)
    raise TypeError.new("long too big to dump: #{d}") if d < -0x80000000 || 0x7fffffff < d
    if d == 0
      byte 0
    elsif 0 < d && d < 123
      byte d + 5
    elsif -124 < d && d < 0
      byte((d - 5) & 0xff)
    else
      buf = []
      begin
        buf << (d & 0xff)
	d >>= 8
      end until d == 0 || d == -1
      byte buf.length
      buf.each {|b| byte b}
    end
  end

  def bytes_str(d)
    long d.length
    @out << d
  end

  def uclass(c)
    byte ?C
    byte ?:
    bytes_str c.name
    yield
  end

  def regexp(str, opts)
    byte ?/
    bytes_str str
    byte opts
  end
end

class Class
  def basic_new
    return Marshal.load(sprintf("\004\006o:%c%s\000", name.length + 5, name))
  end
end

[IO, Binding, Continuation, Data, Dir, File::Stat, MatchData, Method, Proc, Thread, ThreadGroup].each {|c|
  c.class_eval {
    def c.basic_new
      raise TypeError.new("can't basic_new #{self.class}")
    end

    def am_dump(am);
      raise TypeError.new("can't dump #{self.class}")
    end
  }
}

class Object
  def am_dump(am)
    name = yield
    am.print "#{name} = #{am.put(self.class)}.basic_new\n"
    am.put_instance_variables(self, name)
  end
end

class Module
  def Module.basic_new
    return self.new
  end

  def am_dump(am)
    name = self.name
    raise TypeError.new("can't dump anonymous class") if name == ''
    yield name
  end
end

class Array
  def Array.basic_new
    return []
  end

  def am_dump(am)
    name = yield
    am.print "#{name} = Array.new(#{length})\n"
    am.put_instance_variables(self, name)
    self.each_index {|i|
      am.print "#{name}[#{i}] = #{am.put(self[i])}\n"
    }
  end
end

class Exception
  def Exception.basic_new
    return self.new("")
  end

  def am_dump(am)
    name = yield
    am.print "#{name} = Exception.new(#{am.put(self.message)})\n"
    am.put_instance_variables(self, name)
    am.print "#{name}.set_backtrace #{am.put(self.backtrace)}\n"
    # xxx: exception object is created at last.
  end
end

class Hash
  def Hash.basic_new
    return {}
  end

  def am_dump(am)
    name = yield
    am.print "#{name} = Hash.new\n"
    am.put_instance_variables(self, name)
    if self.default != nil
      am.print "#{name}.default = #{am.put(self.default)}\n"
    end
    self.each {|k, v|
      am.print "#{name}[#{am.put(k)}] = #{am.put(v)}\n"
    }
  end
end

class Range
  def Range.basic_new
    return 0...1
  end

  def am_dump(am)
    name = yield
    if self.exclude_end?
      dots = '...'
    else
      dots = '..'
    end
    am.print "#{name} = #{am.put(self.begin)}#{dots}#{am.put(self.end)}\n"
    # xxx: range object is created after `begin' and `end'.
    am.put_instance_variables(self, name)
  end
end

class Regexp
  def Regexp.basic_new(str, opts=nil)
    if self == Regexp
      return Regexp.new(str, opts)
    else
      m = MarshalStringWriter.new
      m.uclass(self) {m.regexp str, opts}
      return Marshal.load(m.out)
    end
  end

  def am_dump(am)
    name = yield
    am.print "#{name} = #{am.put(self.class)}.basic_new(#{self.source.dump}, #{self.options})\n"
    am.put_instance_variables(self, name)
  end
end

class String
  def String.basic_new
    return ""
  end

  def am_dump(am)
    name = yield
    am.print "#{name} = #{self.dump}\n"
    am.put_instance_variables(self, name)
  end
end

class Struct
  def Struct.basic_new
    args = [nil] * self.members.length
    return self.new(*args)
  end

  def am_dump(am)
    name = yield
    args = (["nil"] * self.length).join(", ")
    am.print "#{name} = #{am.put(self.class)}.new(#{args})\n"
    am.put_instance_variables(self, name)
    self.members.each {|m|
      am.print "#{name}[#{am.put(m.intern)}] = #{am.put(self[m])}\n"
    }
  end
end

class Symbol
  def Symbol.basic_new
    return "".intern
  end

  def am_dump(am)
    str = self.to_s
    if /\A[A-Za-z_][0-9A-Za-z_]*\z/ =~ str
      yield ":#{str}"
    else
      name = yield
      am.print "#{name} = #{str.dump}.intern\n"
    end
  end
end

class Time
  def Time.basic_new
    return Time.at(0).utc
  end

  def am_dump(am)
    name = yield
    if self.utc?
      am.print "#{name} = Time.utc(#{year}, #{mon}, #{day}, #{hour}, #{min}, #{sec}, #{usec})\n"
    else
      t = self.dup.utc
      am.print "#{name} = Time.utc(#{t.year}, #{t.mon}, #{t.day}, #{t.hour}, #{t.min}, #{t.sec}, #{t.usec}).localtime\n"
    end
  end
end

class Integer
  def Integer.basic_new
    # Since there is no suitable value for Bignum.basic_new,
    # Bignum.basic_new (and Fixnum.basic_new) returns 0.
    return 0
  end
end

class Fixnum
  def am_dump(am)
    yield self.to_s
  end
end

class Bignum
  def am_dump(am)
    name = yield
    am.print "#{name} = #{self}\n"
    am.put_instance_variables(self, name)
  end
end

class Float
  def Float.basic_new
    return 0.0
  end

  def am_dump(am)
    name = yield
    am.print "#{name} = #{'%.16g' % self}\n"
    am.put_instance_variables(self, name)
  end
end

class TrueClass
  def TrueClass.basic_new
    return true
  end

  def am_dump(am)
    yield "true"
  end
end

class FalseClass
  def FalseClass.basic_new
    return false
  end

  def am_dump(am)
    yield "false"
  end
end

class NilClass
  def NilClass.basic_new
    return nil
  end

  def am_dump(am)
    yield "nil"
  end
end
