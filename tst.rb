require 'amarshal'
require 'tst-marshal'

class AMarshalTest < Test::Unit::TestCase
  include MarshalTestLib
  MarshalClass = AMarshal
  #DebugPrint = true
end
