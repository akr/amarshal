require 'amarshal-pretty'
require 'tst-marshal'

class AMarshalPrettyTest < Test::Unit::TestCase
  include MarshalTestLib
  MarshalClass = AMarshal
  #DebugPrint = true

  def encode(o)
    AMarshal.dump_pretty(o)
  end

  def test_pretty
    assert_equal("[]\n", encode([]))
  end
end
