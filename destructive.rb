class Object
  def become(klass)
    Destructive.change_class(self, klass)
  end

  def set_instance_variable(var, val)
    Destructive.set_iv(self, var, val)
    val
  end
end

class Destructive
  def Destructive.change_class(obj, klass)
    Loader.load(obj) {|o|
      Marshal.load sprintf("\004\006C%s%s", Loader.unique(klass.name), o)
    }
  end

  def Destructive.set_iv(obj, var, val)
    Loader.load(obj) {|o|
      Loader.load(val) {|v|
	Marshal.load sprintf("\004\006I%s\006%s%s", o, Loader.unique(var), v)
      }
    }
  end

  class Loader
    def Loader.unique(name)
      return sprintf(":%c%s", name.length + 5, name)
    end

    @@num = 0
    @@hash = {}

    def Loader.load(obj)
      str = (@@num += 1).to_s
      @@hash[str] = obj
      yield sprintf("u:\030Destructive::Loader%c%s", str.length + 5, str)
      @@hash.delete str
    end

    def Loader._load(str)
      return @@hash[str]
    end
  end
end

class Range
  def first=(val)
    self.set_instance_variable "begin", val
  end
  alias_method("begin=", "first=")

  def last=(val)
    self.set_instance_variable "end", val
  end
  alias_method("end=", "last=")
end

class Exception
  def message=(mesg)
    self.set_instance_variable "mesg", mesg
  end
end

# ruby -rdestructive.rb -e 'o = Object.new; p o; o.become(C = Class.new); p o'
