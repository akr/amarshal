=begin
= amarshal-pretty
amarshal-pretty is highly experimental.
== Methods
--- AMarshal.dump_pretty(obj[, port])
--- AMarshal.load(port)

== TODO
* use X.new/X[] if possible (avoid X.allocate)
=end

require 'amarshal'
require 'prettyprint'
require 'pp'

require 't'

module AMarshal
  def AMarshal.dump_pretty(obj, port='')
    Pretty.new(obj, port).dump_pretty
  end

  class Template
    PrecName = {}
    PrecRight = {}
    PrecLeft = {}
    Arity = {}
    PrettyPrinter = {}
    @curr_prec = 1

    def Template.pretty_printer(f)
      lambda {|out, children, objects|
	#p [f, children, objects]
        i = 0
	f.scan(/[@_$]|[^@_$]+/) {|s|
	  case s
	  when '@'
	    obj = children[i]
	    if Integer === obj
	      obj = objects[obj]
	    end
	    if Template === obj
	      obj.pretty_display out
	    else
	      out.text obj.to_s
	    end
	    i += 1
	  when '_'
	    out.text ' '
	  when '$'
	    out.breakable
	  else
	    out.text s
	  end
	}
      }
    end

    def Template.next_prec(prec, formats, name=nil)
      @curr_prec += 1
      curr_prec(prec, formats, name)
    end

    def Template.curr_prec(prec, formats, name=nil)
      base_prec = @curr_prec
      prec = prec.dup
      #p [base_prec, prec, formats]
      prec.each_index {|i|
	n = prec[i]
	case n
	when Symbol
	  prec[i] = PrecName[n] || n
	when nil
	  prec[i] = nil
	when :min
	  prec[i] = 0
	when :max
	  prec[i] = 1000
	else
	  if n < 0
	    prec[i] = -n
	  else
	    prec[i] = base_prec + n
	  end
	end
      }
      formats.each {|f|
	f = "@_#{f}$@" unless /@/ =~ f 
	f2 = f.gsub(/[_$]/, '')
	PrecLeft[f2] = base_prec
	PrecRight[f2] = prec
	Arity[f2] = f2.count('@')
	PrettyPrinter[f2] = pretty_printer(f)
      }

      if name
	PrecName[name] = base_prec
	PrecRight.each {|format, prec|
	  prec.each_with_index {|n, i|
	    prec[i] = base_prec if n == name
	  }
	}
      end

      -base_prec
    end

    assoc = [0, 0]
    left = [0, 1]
    right = [1, 0]
    nonassoc = [1, 1]

    next_prec left,	%w(if unless while until rescue), :statement
    next_prec left,	%w(or and)
    next_prec right,	%w(not$@)
    next_prec assoc,	%w(@,$@), :arguments
    next_prec nonassoc,	%w(@_=>$@)
    next_prec nonassoc,	%w(defined?$@)
    next_prec right,	%w(= += -= *= /= %= **= &= |= ^= <<= >>= &&= ||=)
    curr_prec [:term, nil, :arguments], %w(@.@_=$@)
    curr_prec [:term, :arguments, :arguments], %w(@[@]_=$@)
    next_prec [1,0,0],	%w(@_?$@_:$@)
    next_prec nonassoc,	%w(@..@ @...@)
    next_prec left,	%w(||)
    next_prec left,	%w(&&)
    next_prec nonassoc,	%w(<=> == === != =~ !~)
    next_prec left,	%w(> <= < <=)
    next_prec left,	%w(| ^)
    next_prec left,	%w(&)
    next_prec left,	%w(<< >>)
    next_prec left,	%w(+ -)
    next_prec left,	%w(* / %)
    next_prec [1],	%w(!@ ~@ +@ -@)
    next_prec right,	%w(**)
    next_prec [0, nil],	%w(@.@), :term
    curr_prec [0, :arguments],	%w(@[@])
    curr_prec [0, nil, :arguments], %w(@.@(@))
    next_prec [:arguments],	%w([@] {@})

    #pp PrecRight
    #pp PrettyPrinter

    def Template.create(format, objs=nil, objects=[])
      Template.new(format, objects) {|t|
	t.add_obj *objs if objs
	yield t if block_given?
      }
    end

    def initialize(format, objects)
      raise "unknown format: #{format.inspect}" unless PrecRight.include? format
      @format = format
      @children = []
      @objects = objects
      yield self
    end

    def map_object!(&block)
      @objects.map!(&block)
    end

    def add_obj(*objs)
      objs.each {|obj|
	if PrecRight[@format][@children.size] == nil
	  @children << obj
	else
	  @children << @objects.size
	  @objects << obj
	end
      }
    end

    def add_exp(format, objs=nil, &block)
      t = Template.create(format, objs, @objects, &block)
      @children << t
      t
    end

    def prec
      PrecLeft[@format]
    end

    def to_s
      if @children.length != Arity[@format]
	raise "expected #{Arity[@format]} arguments for #{@format.inspect} but #{@children.length}"
      end
      arg_precs = PrecRight[@format]
      i = 0
      @format.gsub(/@/) {
	arg = @objects[@children[i]]
	prec = arg_precs[i]
	i += 1
	if Template === arg
	  #p [prec, arg, arg.prec]
	  if prec <= arg.prec
	    arg.to_s
	  else
	    '(' + arg.to_s + ')'
	  end
	else
	  arg.to_s
	end
      }
    end

    def display(out)
      out << self.to_s
    end

    def pretty_display(out)
      PrettyPrinter[@format].call(out, @children, @objects)
    end
  end

  class Pretty
    def initialize(obj, port='')
      @obj = obj
      @port = port
      @varnum = 0
    end

    def display_template(template)
      if Template === template
	PrettyPrint.format(@port) {|out|
	  template.pretty_display out
	}
	@port << "\n"
      else
	@port << template.to_s << "\n"
      end
    end

    def gensym
      @port << "v = []\n" if @varnum == 0
      "v[#{(@varnum += 1) - 1}]"
    end

    def dump_pretty
      @count = Hash.new(0)
      count(@obj)

      @visiting = {}
      @names = {}
      template = visit(@obj)
      display_template template
    end

    def count(obj)
      id = obj.__id__
      @count[id] += 1
      return if 1 < @count[id]

      init_proc = lambda {|init_method, *init_args|
		    init_args.each {|arg| count(arg)}
		  }

      obj.am_nameinit( lambda {|name|}, init_proc) and return
      obj.am_litinit(lambda {|lit|}, init_proc) and return
      obj.am_allocinit(
	lambda {|alloc_receiver, alloc_method, *alloc_args|
	  count alloc_receiver
	  alloc_args.each {|arg| count(arg)}
	},
	init_proc)
    end

    def visit(obj)
      id = obj.__id__
      if @names.include? id
	#p [:visit_named, obj, @names[id]]
	if @names[id] == :should_not_refer
	  raise StandardError.new(":should_not_refer is refered: " + obj.inspect)
	end
        @names[id]
      elsif !@visiting.include?(id)
	#p [:visit_first, obj]
        ret = visit_first(obj, id)
	if !@names.include? id
	  raise StandardError.new("visit_first doesn't name a object")
	end
	#p [:visit_first_ret, obj, ret]
	ret
      else
	#p [:visit_second, obj]
	@names[id] = :should_be_named
        ret = visit_second(obj, id)
	if @names[id] == :should_be_named
	  raise StandardError.new("visit_second doesn't name a object")
	end
	#p [:visit_second, obj, ret]
	ret
      end
    end

    def visit_first(obj, id)
      @visiting[id] = true

      if obj.respond_to?(:am_compound_literal) && (t = obj.am_compound_literal)
	templates = {}
	if Template === t
	  t.map_object! {|child|
	    break if @visiting[id] != true
	    templates[child.__id__] = visit(child)
	  }
	end
	if @visiting[id] == true
	  if 1 < @count[id]
	    name = gensym
	    display_template Template.create('@=@', [name, t])
	    t = @names[id] = name
	  else
	    @names[id] = :should_not_refer
	  end
	  return t
	end

	name = @names[id] 
	@visiting[id].each {|init_method, *init_args|
	  display_template AMarshal.template_call(name, init_method,
						  init_args.map {|arg| templates.fetch(arg.__id__) { visit(arg) }})
	}
	result = name
      else
	obj.am_nameinit(
	  lambda {|name| @names[id] = name},
	  lambda {|init_method, *init_args|
	    display_template AMarshal.template_call(@names[id], init_method, init_args.map {|arg| visit(arg)})
	  }) and
	  return @names[id]

	template = nil
	inits = []
	obj.am_templateinit(lambda {|template|}, lambda {|init| inits << init})
	template.map_object! {|o| visit(o)} if Template === template
	  
	if 1 < @count[id] || !inits.empty?
	  @names[id] = name = gensym
	  display_template Template.create('@=@', [name, template])
	  inits.each {|init_method, *init_args|
	    display_template AMarshal.template_call(name, init_method, init_args.map {|arg| visit(arg)})
	  }
	  result = name
	else
	  @names[id] = :should_not_refer
	  result = template
	end
      end

      @visiting.delete id
      result
    end

    def visit_second(obj, id)
      inits = []

      obj.am_nameinit(
	lambda {|name| @names[id] = name},
	lambda {|init| inits << init}) and
	begin
	  @visiting[id] = inits
	  return @names[id]
	end

      @names[id] = name = gensym

      obj.am_litinit(
	lambda {|lit| @port << "#{name} = #{lit}\n"},
	lambda {|init| inits << init}) and
	begin
	  @visiting[id] = inits
	  return @names[id]
	end

      obj.am_allocinit(
	lambda {|alloc_receiver, alloc_method, *alloc_args|
	  receiver = visit(alloc_receiver)
	  args = alloc_args.map {|arg| visit(arg)}
	  @port << "#{name} = "
	  display_template AMarshal.template_call(receiver, alloc_method, args)
	},
	lambda {|init| inits << init})

      @visiting[id] = inits
      return @names[id]
    end
  end

  def AMarshal.template_call(receiver, method, args)
    case method
    when :[]=
      AMarshal::Template.create('@[@]=@', [receiver, *args])
    when :<<
      AMarshal::Template.create('@<<@', [receiver, *args])
    else
      method = method.to_s
      if /\A([A-Za-z_][0-9A-Za-z_]*)=\z/ =~ method
	# receiver.m = arg0
	AMarshal::Template.create('@.@=@', [receiver, $1, *args])
      else
	if args.empty?
	  # receiver.m
	  AMarshal::Template.create('@.@', [receiver, method])
	else
	  # receiver.m(arg0, ...)
	  AMarshal::Template.create('@.@(@)', [receiver, method]) {|s|
	    (0...(args.length-1)).each {|i|
	      arg = args[i]
	      s = s.add_exp('@,@', [arg])
	    }
	    s.add_obj args[-1]
	  }
	end
      end
    end
  end
end

class Object
  def am_templateinit(template_proc, init_proc)
    am_litinit(
      lambda {|lit|
        template_proc.call(lit)
      },
      init_proc) ||
    am_allocinit(
      lambda {|alloc_receiver, alloc_method, *alloc_args|
	t = AMarshal.template_call(alloc_receiver, alloc_method, alloc_args)
	template_proc.call(t)
      },
      init_proc)
  end
end

class Array
  def am_compound_literal
    return nil unless self.instance_variables.empty?

    if self.class == Array
      if self.empty?
        '[]'
      else
	AMarshal::Template.create('[@]') {|s|
	  t = s
	  (0...(self.length-1)).each {|i|
	    arg = self[i]
	    s = s.add_exp('@,@', [arg])
	  }
	  s.add_obj self[-1]
	}
      end
    else
      if self.empty?
	AMarshal::Template.create('@[@]', [self.class.name, ''])
      else
	AMarshal::Template.create('@[@]', [self.class.name]) {|s|
	  (0...(self.length-1)).each {|i|
	    arg = self[i]
	    s = s.add_exp('@,@', [arg])
	  }
	  s.add_obj self[-1]
	}
      end
    end
  end
end

class Hash
  def am_compound_literal
    return nil unless self.instance_variables.empty?
    return nil if self.default

    if self.class == Hash
      if self.empty?
        '{}'
      else
	# {k1 => v1, ...}
	AMarshal::Template.create('{@}') {|s|
	  first = true
	  k0 = nil
	  v0 = nil
	  self.each {|k1, v1|
	    unless first
	      s = s.add_exp('@,@') {|r|
	        r.add_exp('@=>@', [k0, v0])
	      }
	    end
	    k0, v0 = k1, v1
	    first = false
	  }
	  s.add_exp('@=>@', [k0, v0])
	}

      end
    else
      if self.empty?
	# C[]
	AMarshal::Template.create('@[@]', [self.class.name, ''])
      else
	# C[k1, v1, ...]
	AMarshal::Template.create('@[@]', [self.class.name]) {|s|
	  first = true
	  k0 = nil
	  v0 = nil
	  self.each {|k1, v1|
	    unless first
	      s = s.add_exp('@,@') {|r|
	        r.add_exp('@,@', [k0, v0])
	      }
	    end
	    k0, v0 = k1, v1
	    first = false
	  }
	  s.add_exp('@=>@', [k0, v0])
	}
      end
    end
  end
end

class Range
  def am_compound_literal
    return nil unless self.instance_variables.empty?
    if self.class == Range
      if self.exclude_end?
	AMarshal::Template.create('@...@', [first, last])
      else
	AMarshal::Template.create('@..@', [first, last])
      end
    else
      if self.exclude_end?
	# C.new(a, b)
	AMarshal::Template.create('@.@(@)', [self.class.name, 'new']) {|s|
	  s.add_exp('@,@', [first, last])
	}
      else
	# C.new(a, b, true)
	AMarshal::Template.create('@.@(@)', [self.class.name, 'new']) {|s|
	  s.add_exp('@,@') {|s|
	    s.add_exp('@,@', [first, last])
	    s.add_obj 'true'
	  }
	}
      end
    end
  end
end
