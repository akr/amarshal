require 'amarshal-pretty'
require 'tst-marshal'

class AMarshalPrettyTest < RUNIT::TestCase
  include MarshalTestLib
  MarshalClass = AMarshal
  #DebugPrint = true

  def encode(o)
    AMarshal.dump_pretty(o)
  end
end

if $0 == __FILE__
  RUNIT::CUI::TestRunner.run(AMarshalPrettyTest.suite)
end
