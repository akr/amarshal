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
require 'rubyexpression'
require 'pp'

module AMarshal
  def AMarshal.dump_pretty(obj, port='')
    Pretty.new(obj, port).dump_pretty
  end

  class Template
    def initialize(format, objs)
      @format = format
      @objs = objs
      @names = []

      case @format
      when '@=@'
	@conv = lambda {
	  RubyExpression.binary_exp(
	    convert_to_ruby_expression(@objs[0]), '=',
	    convert_to_ruby_expression(@objs[1]))
	}
      when '@[@]=@'
	@conv = lambda {
	  RubyExpression.binary_exp(
	    RubyExpression.method_call(
	      convert_to_ruby_expression(@objs[0]), '[]',
	      convert_to_ruby_expression(@objs[1])),
	    '=',
	    convert_to_ruby_expression(@objs[2]))
	}
      when '@<<@'
	@conv = lambda {
	  RubyExpression.binary_exp(
	    convert_to_ruby_expression(@objs[0]),
	    '<<',
	    convert_to_ruby_expression(@objs[1]))
	}
      when '@.@=@'
	@names << @objs.slice!(1)
	@conv = lambda {
	  RubyExpression.binary_exp(
	    RubyExpression.method_call(convert_to_ruby_expression(@objs[0]), @names[0]), '=',
	    convert_to_ruby_expression(@objs[1]))
	}
      when '@.@'
	@names << @objs.slice!(1)
	@conv = lambda {
	  RubyExpression.method_call(convert_to_ruby_expression(@objs[0]), @names[0])
	}
      when '@.@(@)'
	@names << @objs.slice!(1)
	@conv = lambda {
	  RubyExpression.method_call(
	    convert_to_ruby_expression(@objs[0]), @names[0],
	    @objs[1..-1].map {|o| convert_to_ruby_expression(o)})
	}
      when '[@]'
	@conv = lambda {
	  RubyExpression.array(@objs.map {|o| convert_to_ruby_expression(o)})
	}
      when '@[@]'
	@conv = lambda {
	  RubyExpression.method_call(
	    convert_to_ruby_expression(@objs[0]), '[]',
	    convert_to_ruby_expression(@objs[1]))
	}
      when '{@}'
	@conv = lambda {
	  RubyExpression.hash(@objs.map {|o| convert_to_ruby_expression(o)})
	}
      when '@...@'
	@conv = lambda {
	  RubyExpression.binary_exp(
	    convert_to_ruby_expression(@objs[0]), '...',
	    convert_to_ruby_expression(@objs[1]))
	}
      when '@..@'
	@conv = lambda {
	  RubyExpression.binary_exp(
	    convert_to_ruby_expression(@objs[0]), '..',
	    convert_to_ruby_expression(@objs[1]))
	}
      else
        raise "unknown format: #{@format.inspect}"
      end
    end

    def map_object!(&block)
      @objs.map!(&block)
    end

    def convert_to_ruby_expression(obj)
      if Template === obj
        obj.to_ruby_expression
      else
        obj.to_s
      end
    end

    def to_ruby_expression
      @conv.call
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
	template.to_ruby_expression.pretty_display @port
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
	    display_template Template.new('@=@', [name, t])
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
	  display_template Template.new('@=@', [name, template])
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
      AMarshal::Template.new('@[@]=@', [receiver, *args])
    when :<<
      AMarshal::Template.new('@<<@', [receiver, *args])
    else
      method = method.to_s
      if /\A([A-Za-z_][0-9A-Za-z_]*)=\z/ =~ method
	# receiver.m = arg0
	AMarshal::Template.new('@.@=@', [receiver, $1, *args])
      else
	if args.empty?
	  # receiver.m
	  AMarshal::Template.new('@.@', [receiver, method])
	else
	  # receiver.m(arg0, ...)
	  AMarshal::Template.new('@.@(@)', [receiver, method, *args])
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
	AMarshal::Template.new('[@]', Array.new(self))
      end
    else
      if self.empty?
	AMarshal::Template.create('@[@]', [self.class.name, ''])
      else
	AMarshal::Template.create('@[@]', [self.class.name, *self])
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
	objs = []
	self.map {|k, v|
	  objs << k
	  objs << v
	}
	AMarshal::Template.new('{@}', objs)
      end
    else
      if self.empty?
	# C[]
	AMarshal::Template.new('@[@]', [self.class.name, ''])
      else
	# C[k1, v1, ...]
	objs = [self.class.name]
	self.map {|k, v|
	  objs << k
	  objs << v
	}
	AMarshal::Template.new('@[@]', objs)
      end
    end
  end
end

class Range
  def am_compound_literal
    return nil unless self.instance_variables.empty?
    if self.class == Range
      if self.exclude_end?
	AMarshal::Template.new('@...@', [first, last])
      else
	AMarshal::Template.new('@..@', [first, last])
      end
    else
      if self.exclude_end?
	# C.new(a, b)
	AMarshal::Template.new('@.@(@)', [self.class.name, 'new', first, last])
      else
	# C.new(a, b, true)
	AMarshal::Template.new('@.@(@)', [self.class.name, 'new', first, last, 'true'])
      end
    end
  end
end
