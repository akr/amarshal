require 'amarshal'
require 'tst-marshal'

class AMarshalTest < RUNIT::TestCase
  include MarshalTestLib
  MarshalClass = AMarshal
  #DebugPrint = true
end

if $0 == __FILE__
  RUNIT::CUI::TestRunner.run(AMarshalTest.suite)
end
