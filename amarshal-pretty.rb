=begin

= status
amarshal-pretty is highly experimental.

= TODO

* remove useless parenthesis by operator preferences.
* use X.new/X[] if possible (avoid X.allocate)
* indent using pretty-print

=end
require 'amarshal'
require 'pp'

module AMarshal
  def AMarshal.dump_pretty(obj, port='')
    Pretty.new(obj, port).dump_pretty
  end

  class Template < Array
    def add_object(obj)
      self << "" if self.size % 2 == 0
      self << obj
    end

    def add_string(str)
      self << "" if self.size % 2 == 0
      self.last << str
    end

    def map_object!
      each_with_index {|elt, i|
        next if i % 2 == 0
	self[i] = yield elt
      }
    end
  end

  class Pretty
    def initialize(obj, port='')
      @obj = obj
      @port = port
      @varnum = 0
    end

    def gensym
      "v#{@varnum += 1}"
    end

    def dump_pretty
      @count = Hash.new(0)
      count(@obj)

      @visiting = {}
      @names = {}
      template = visit(@obj)
      @port << template.to_s << "\n"
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
	t.map_object! {|child|
	  break if @visiting[id] != true
	  templates[child.__id__] = visit(child)
	}
	if @visiting[id] == true
	  if 1 < @count[id]
	    name = gensym
	    @port << "#{name} = #{t.to_s}\n"
	    t = @names[id] = name
	  else
	    @names[id] = :should_not_refer
	  end
	  return t
	end

	name = @names[id] 
	@visiting[id].each {|init_method, *init_args|
	  AMarshal.dump_call(@port, name, init_method,
	                     init_args.map {|arg| templates.fetch(arg.__id__) { visit(arg) }})
	}
	name
      else
	obj.am_nameinit(
	  lambda {|name| @names[id] = name},
	  lambda {|init_method, *init_args|
	    AMarshal.dump_call(@port, @names[id], init_method, init_args.map {|arg| visit(arg)})
	  }) and
	  return @names[id]

	inits = []

	lit = nil
	obj.am_litinit(lambda {|lit|}, lambda {|init| inits << init}) and
	  begin
	    if 1 < @count[id] || !inits.empty?
	      @names[id] = name = gensym
	      @port << "#{name} = #{lit}\n"
	      inits.each {|init_method, *init_args|
		AMarshal.dump_call(@port, name, init_method, init_args.map {|arg| visit(arg)})
	      }
	      return name
	    else
	      @names[id] = :should_not_refer
	      return lit
	    end
	  end

	alloc = nil
	obj.am_allocinit(lambda {|alloc|}, lambda {|init| inits << init})

	alloc_receiver, alloc_method, *alloc_args = alloc
	receiver = visit(alloc_receiver)
	args = alloc_args.map {|arg| visit(arg)}
	if 1 < @count[id] || !inits.empty?
	  @names[id] = name = gensym
	  @port << "#{name} = "
	  AMarshal.dump_call(@port, receiver, alloc_method, args)
	  inits.each {|init_method, *init_args|
	    AMarshal.dump_call(@port, name, init_method, init_args.map {|arg| visit(arg)})
	  }
	else
	  @names[id] = :should_not_refer
	  return '(' + AMarshal.dump_call('', receiver, alloc_method, args).chomp + ')'
	end
      end

      @visiting.delete id

      @names[id]
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
	  AMarshal.dump_call(@port, receiver, alloc_method, args)
	},
	lambda {|init| inits << init})

      @visiting[id] = inits
      return @names[id]
    end
  end
end

class Array
  def am_compound_literal
    return nil unless self.instance_variables.empty?
    t = AMarshal::Template.new
    unless self.class == Array
      t.add_string self.class.name
    end
    if length == 0
      t.add_string "[]"
    else
      sep = '['
      self.each {|obj|
	t.add_string sep
	t.add_object obj
	sep = ','
      }
      t.add_string ']'
    end
    t
  end
end

class Hash
  def am_compound_literal
    return nil unless self.instance_variables.empty?
    return nil if self.default
    if self.class == Hash
      beg_str = '{'
      assoc_sep = '=>'
      end_str = '}'
    else
      beg_str = self.class.name + '['
      assoc_sep = ','
      end_str = ']'
    end
    t = AMarshal::Template.new
    if size == 0
      t.add_string beg_str
      t.add_string end_str
    else
      sep = beg_str
      self.each {|k, v|
	t.add_string sep
	t.add_object k
	t.add_string assoc_sep
	t.add_object v
	sep = ','
      }
      t.add_string end_str
    end
    t
  end
end

class Range
  def am_compound_literal
    return nil unless self.instance_variables.empty?
    t = AMarshal::Template.new
    if self.class == Range
      beg_str = '('
      sep_str = (exclude_end? ? '...' : '..')
      end_str = ')'
    else
      beg_str = self.class.name + '.new('
      sep_str = ','
      end_str = (exclude_end? ? ', true' : '') + ')'
    end
    t.add_string beg_str
    t.add_object first
    t.add_string sep_str
    t.add_object last
    t.add_string end_str
    t
  end
end
