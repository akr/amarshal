require 'test/unit'

module MarshalTestLib
  DebugPrint = false
  MarshalClass = Marshal

  def encode(o)
    self.class::MarshalClass.dump(o)
  end

  def decode(s)
    self.class::MarshalClass.load(s)
  end

  def marshaltest(o1)
    #o1.instance_eval { remove_instance_variable '@v' if defined? @v }
    str = encode(o1)
    print str, "\n" if self.class::DebugPrint
    o2 = decode(str)
    o2
  end

  def marshal_equal(o1)
    o2 = marshaltest(o1)
    assert_equal(o1.class, o2.class)
    iv1 = o1.instance_variables.sort
    iv2 = o2.instance_variables.sort
    assert_equal(iv1, iv2)
    val1 = iv1.map {|var| o1.instance_eval {eval var}}
    val2 = iv1.map {|var| o2.instance_eval {eval var}}
    assert_equal(val1, val2)
    if block_given?
      assert_equal(yield(o1), yield(o2))
    else
      assert_equal(o1, o2)
    end
  end

  class MyObject; def initialize(v) @v = v end; attr_reader :v; end
  def test_object
    o1 = Object.new
    o1.instance_eval { @iv = 1 }
    marshal_equal(o1) {|o| o.instance_eval { @iv }}
    marshal_equal(MyObject.new(2)) {|o| o.v}
  end

  class MyArray < Array; def initialize(v, *args) super args; @v = v; end end
  def test_array
    marshal_equal([1,2,3])
    marshal_equal(MyArray.new(0, 1,2,3))
  end

  class MyException < Exception; def initialize(v, *args) super(*args); @v = v; end; attr_reader :v; end
  def test_exception
    marshal_equal(Exception.new('foo')) {|o| o.message}
    marshal_equal(MyException.new(20, "bar")) {|o| [o.message, o.v]}
  end

  def test_false
    marshal_equal(false)
  end

  class MyHash < Hash; def initialize(v, *args) super(*args); @v = v; end end
  def test_hash
    marshal_equal({1=>2, 3=>4})
    h = Hash.new(:default)
    h[5] = 6
    marshal_equal(h)
    h = MyHash.new(7, 8)
    h[4] = 5
    marshal_equal(h)
    h = Hash.new {}
    assert_raises(TypeError) { marshaltest(h) }
  end

  def test_bignum
    marshal_equal(-0x4000_0000_0000_0001)
    marshal_equal(-0x4000_0001)
    marshal_equal(0x4000_0000)
    marshal_equal(0x4000_0000_0000_0000)
  end

  def test_fixnum
    marshal_equal(-0x4000_0000)
    marshal_equal(-1)
    marshal_equal(0)
    marshal_equal(1)
    marshal_equal(0x3fff_ffff)
  end

  def test_float
    marshal_equal(-1.0)
    marshal_equal(0.0)
    marshal_equal(1.0)
    marshal_equal(1.0/0.0)
    marshal_equal(-1.0/0.0)
    marshal_equal(0.0/0.0) {|o| o.nan?}
    marshal_equal(-0.0) {|o| 1.0/o}
  end

  class MyRange < Range; def initialize(v, *args) super(*args); @v = v; end end
  def test_range
    marshal_equal(1..2)
    marshal_equal(1...3)
    marshal_equal(MyRange.new(4,5,8, false))
  end

  class MyRegexp < Regexp; def initialize(v, *args) super(*args); @v = v; end end
  def test_regexp
    marshal_equal(/a/)
    marshal_equal(MyRegexp.new(10, "a"))
  end

  class MyString < String; def initialize(v, *args) super(*args); @v = v; end end
  def test_string
    marshal_equal("abc")
    marshal_equal(MyString.new(10, "a"))
  end

  MyStruct = Struct.new("MyStruct", :a, :b)
  class MySubStruct < MyStruct; def initialize(v, *args) super(*args); @v = v; end end
  def test_struct
    marshal_equal(MyStruct.new(1,2))
    marshal_equal(MySubStruct.new(10,1,2))
  end

  def test_symbol
    marshal_equal(:a)
    marshal_equal(:a?)
    marshal_equal(:a!)
    marshal_equal(:a=)
    marshal_equal(:|)
    marshal_equal(:^)
    marshal_equal(:&)
    marshal_equal(:<=>)
    marshal_equal(:==)
    marshal_equal(:===)
    marshal_equal(:=~)
    marshal_equal(:>)
    marshal_equal(:>=)
    marshal_equal(:<)
    marshal_equal(:<=)
    marshal_equal(:<<)
    marshal_equal(:>>)
    marshal_equal(:+)
    marshal_equal(:-)
    marshal_equal(:*)
    marshal_equal(:/)
    marshal_equal(:%)
    marshal_equal(:**)
    marshal_equal(:~)
    marshal_equal(:+@)
    marshal_equal(:-@)
    marshal_equal(:[])
    marshal_equal(:[]=)
    marshal_equal(:`) # `
    marshal_equal("a b".intern)
  end

  class MyTime < Time; def initialize(v, *args) super(*args); @v = v; end end
  def test_time
    marshal_equal(Time.now)
    marshal_equal(MyTime.new(10))
  end

  def test_true
    marshal_equal(true)
  end

  def test_nil
    marshal_equal(nil)
  end

  def test_share
    o = [:share]
    o1 = [o, o]
    o2 = marshaltest(o1)
    assert_same(o2.first, o2.last)
  end

  class CyclicRange < Range
    def <=>(other) self.object_id <=> other.object_id end
  end
  def test_cyclic_range
    o1 = CyclicRange.allocate
    o1.instance_eval { initialize o1, o1 }
    o2 = marshaltest(o1)
    assert_same(o2, o2.begin)
    assert_same(o2, o2.end)
  end

  def test_singleton
    o = Object.new
    def o.m() end
    assert_raises(TypeError) { marshaltest(o) }
    o = Object.new
    class << o
      @v = 1
    end
    assert_raises(TypeError) { marshaltest(o) }
    assert_raises(TypeError) { marshaltest(ARGF) }
    assert_raises(TypeError) { marshaltest(ENV) }
  end

  module Mod1 end
  module Mod2 end
  def test_extend
    o = Object.new
    o.extend Mod1
    marshal_equal(o) {|obj| obj.kind_of? Mod1}
    o = Object.new
    o.extend Module.new
    assert_raises(TypeError) { marshaltest(o) }
    o = Object.new
    o.extend Mod1
    o.extend Mod2
    marshal_equal(o) {|obj| class << obj; ancestors end}
  end

  def test_anonymous
    c = Class.new
    assert_raises(TypeError) { marshaltest(c) }
    o = c.new
    assert_raises(TypeError) { marshaltest(o) }
    m = Module.new
    assert_raises(TypeError) { marshaltest(m) }
  end
end

class MarshalTest < Test::Unit::TestCase
  include MarshalTestLib
end
