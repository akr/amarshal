require 'amarshal'

require 'runit/testcase'
require 'runit/cui/testrunner'

class AMarshalTest < RUNIT::TestCase
  def marshal_equal(o1)
    o2 = AMarshal.load(AMarshal.dump(o1))
    assert_equal(o1.class, o2.class)
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

  class MyArray < Array; def initialize(v, *arr) super arr; @v = v; end; attr_reader :v; end
  def test_array
    marshal_equal([1,2,3])
    marshal_equal(MyArray.new(0, [1,2,3])) {|o| [o, o.v]}
  end

  def test_exception
    o1 = Exception.new('foo')
    marshal_equal(o1) {|o| o.message}
  end

  def test_false
    marshal_equal(false)
  end

  def test_hash
    marshal_equal({1=>2, 3=>4})
  end

  def test_bignum
    marshal_equal(1000000000000000)
  end

  def test_fixnum
    marshal_equal(1)
  end

  def test_float
    marshal_equal(1.0)
  end

  def test_range
    marshal_equal(1..2)
    marshal_equal(1..3)
  end

  class MyRegexp < Regexp; def initialize(v, *args) super *args; @v = v; end; attr_reader :v; end
  def test_regexp
    marshal_equal(/a/)
    marshal_equal(MyRegexp.new(10, "a")) {|o| [o, o.v]}
  end

  def test_string
    marshal_equal("abc")
  end

  MyStruct = Struct.new("MyStruct", :a, :b)
  def test_struct
    marshal_equal(MyStruct.new(1,2))
  end

  def test_symbol
    marshal_equal(:a)
  end

  def test_time
    marshal_equal(Time.now)
  end

  def test_true
    marshal_equal(true)
  end

  def test_nil
    marshal_equal(nil)
  end

end

RUNIT::CUI::TestRunner.run(AMarshalTest.suite)
