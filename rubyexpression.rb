require 'prettyprint'

class RubyExpression
  @curr_prec = 1
  def RubyExpression.inherited(c)
    return if c.superclass != RubyExpression
    c.const_set(:Prec, @curr_prec)
    @curr_prec += 1
  end

  def enclose_display(obj, c, out)
    if RubyExpression === obj
      c = c::Prec if Class === c
      obj = Parenthesis.new(obj) if obj.class::Prec < c
      out.group(1) {
	obj.pretty_format out
      }
    else
      out.text obj.to_s
    end
  end

  def to_s
    result = ''
    self.display(result)
    result
  end

  def pretty_display(out=$>)
    PrettyPrint.format(out) {|pout| pretty_format(pout)}
  end

  def display(out=$>)
    PrettyPrint.singleline_format(out) {|pout| pretty_format(pout)}
  end

  BinaryOperators = {}
  def RubyExpression.define_binary_operator(assoc, ops, space=true)
    case assoc
    when :left
      off1, off2 = 0, 1
    when :right
      off1, off2 = 1, 0
    when :nonassoc
      off1, off2 = 1, 1
    when :assoc
      off1, off2 = 0, 0
    else
      raise "unknown associativity: #{assoc}"
    end
    c = Class.new(RubyExpression) {
      def initialize(arg1, op, arg2)
	@op = op
	@arg1 = arg1
	@arg2 = arg2
      end
      define_method(:pretty_format) {|out|
	enclose_display(@arg1, self.class::Prec+off1, out)
	out.text ' ' if space
	out.text @op
	out.breakable(space ? ' ' : '')
	enclose_display(@arg2, self.class::Prec+off2, out)
      }
    }
    #p [c::Prec, *ops]
    ops.each {|op|
      BinaryOperators[op] = c
    }
  end

  UnaryOperators = {}
  def RubyExpression.define_unary_operator(ops, space=true)
    c = Class.new(RubyExpression) {
      def initialize(op, arg)
	@op = op
	@arg = arg
      end

      define_method(:pretty_format) {|out|
	out.text @op
	out.text ' ' if space
	enclose_display(@arg, self.class::Prec+1, out)
      }
    }
    ops.each {|op|
      UnaryOperators[op] = c
    }
  end

  define_binary_operator(:left, %w{if unless while until rescue})
  define_binary_operator(:left, %w{or and})
  define_unary_operator(%w{not})

  class Arguments < RubyExpression
    # v1, v2, v3, ...
    def initialize(args)
      @args = args
    end

    def pretty_format(out)
      @args.each {|arg|
	unless out.first?
	  out.text ','
	  out.breakable
	end
	enclose_display(arg, Arguments, out)
      }
    end
  end

  define_binary_operator(:nonassoc, %w{=>})
  define_unary_operator(%w{defined?})
  define_binary_operator(:right,
    %w{= += -= *= /= %= **= &= |= ^= <<= >>= &&= ||=})

  class Conditional < RubyExpression
    # @ ? @ : @
    def initialize(arg1, arg2, arg3)
      @arg1 = arg1
      @arg2 = arg2
      @arg3 = arg3
    end

    def pretty_format(out)
      enclose_display(arg1, Conditional::Prec+1, out)
      out.text ' ?'
      out.breakable
      enclose_display(arg2, Conditional, out)
      out.text ' :'
      out.breakable
      enclose_display(arg3, Conditional, out)
    end
  end

  define_binary_operator(:nonassoc, %w{.. ...}, false)
  define_binary_operator(:left, %w{||})
  define_binary_operator(:left, %w{&&})
  define_binary_operator(:nonassoc, %w{<=> == === != =~ !~})
  define_binary_operator(:left, %w{> <= < <=})
  define_binary_operator(:left, %w{| ^})
  define_binary_operator(:left, %w{&})
  define_binary_operator(:left, %w{<< >>})
  define_binary_operator(:left, %w{+ -})
  define_binary_operator(:left, %w{* / %})
  define_unary_operator(%w{! ~ + -}, false)
  define_binary_operator(:right, %w{**})

  class MethodCall < RubyExpression
    # @[@] @.@ @.@(@)
    def initialize(receiver, methodname, args)
      @receiver = receiver
      @methodname = methodname
      @args = args
    end

    def pretty_format(out)
      enclose_display(@receiver, MethodCall, out)
      if @methodname == "[]"
	out.group(1, '[', ']') {
	  Arguments.new(@args).pretty_format out
	}
      else
	out.text '.'
	out.text @methodname
        unless @args.empty?
	  out.group(1, '(', ')') {
	    Arguments.new(@args).pretty_format out
	  }
	end
      end
    end
  end

  class Parenthesis < RubyExpression
    # (@) [@] {@}
    def initialize(exp, left='(', right=')')
      @exp = exp
      @left = left
      @right = right
    end

    def pretty_format(out)
      out.group(1, @left, @right) {
	@exp.pretty_format out
      }
    end
  end

  def RubyExpression.binary_exp(arg1, op, arg2)
    BinaryOperators[op].new(arg1, op, arg2)
  end

  def RubyExpression.unary_exp(op, arg)
    UnaryOperators[op].new(op, arg)
  end

  def RubyExpression.array(args)
    Parenthesis.new(Arguments.new(args), '[', ']')
  end

  def RubyExpression.hash(args)
    arr = []
    0.step(args.length-1, 2) {|i|
      arr << binary_exp(args[i], '=>', args[i+1])
    }
    Parenthesis.new(Arguments.new(arr), '{', '}')
  end

  def RubyExpression.method_call(receiver, methodname, args=[])
    MethodCall.new(receiver, methodname, args)
  end
end

=begin
e = RubyExpression.unary_exp('not', 'z')
e = RubyExpression.unary_exp('not', e)
e = RubyExpression.unary_exp('not', e)
e = RubyExpression.unary_exp('not', e)
e = RubyExpression.unary_exp('not', e)
e = RubyExpression.unary_exp('not', e)
e = RubyExpression.binary_exp(e, '=>', e)
e = RubyExpression::Arguments.new([e,e,e,e,e])
e = RubyExpression::Parenthesis.new(e, '{', '}')
e = RubyExpression.binary_exp(e, '+', e)
e.pretty_display STDOUT
puts
=end
