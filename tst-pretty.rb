require 'tst'
require 'amarshal-pretty'

class AMarshalPrettyTest < RUNIT::TestCase
  include AMarshalTestLib

  def marshaltest(o1)
    str = AMarshal.dump_pretty(o1)
    o2 = AMarshal.load(str)
    #print str; print "\n"
    o2
  end
end

if $0 == __FILE__
  RUNIT::CUI::TestRunner.run(AMarshalPrettyTest.suite)
end
