--[[
	PropertyBinding tests.
]]

local UnitTest = Shine.UnitTest
local PropertyBinding = require "shine/lib/gui/binding/property"

UnitTest:Test( "Should destroy itself if no targets remain and AutoDestroy is true", function( Assert )
	local Source = {
		AddListener = UnitTest.MockFunction(),
		RemoveListener = UnitTest.MockFunction()
	}

	local Binding = PropertyBinding():From( Source ):To( {
		{ Sink = function() end },
		{ Sink = function() end }
	} )

	Binding:RemoveTarget( Binding.Targets[ 1 ] )
	Assert.Equals( "Should not have destroyed itself yet", 0, #Source.RemoveListener.Invocations )

	Binding:RemoveTarget( Binding.Targets[ 1 ] )
	Assert.DeepEquals( "Should have destroyed itself", {
		{
			ArgCount = 2,
			Source,
			Binding
		}
	}, Source.RemoveListener.Invocations )
end )
