--[[
	MultiPropertyBinding tests.
]]

local UnitTest = Shine.UnitTest
local MultiPropertyBinding = require "shine/lib/gui/binding/multi_property"

UnitTest:Test( "Should add/remove sources as expected", function( Assert )
	local Source = {
		AddListener = UnitTest.MockFunction(),
		RemoveListener = UnitTest.MockFunction()
	}

	local Binding = MultiPropertyBinding():From( { Source } )

	Assert.ArrayEquals( "Should have set the source", { Source }, Binding.Sources )
	Assert.DeepEquals( "Should have invoked AddListener with the binding", {
		{
			ArgCount = 2,
			Source,
			Binding
		}
	}, Source.AddListener.Invocations )

	Binding:RemoveSource( Source )

	Assert.Equals( "Sources should be empty after removing", 0, #Binding.Sources )
	Assert.DeepEquals( "Should have invoked RemoveListener with the binding", {
		{
			ArgCount = 2,
			Source,
			Binding
		}
	}, Source.RemoveListener.Invocations )
end )

UnitTest:Test( "Should add/remove targets as expected", function( Assert )
	local Targets = {
		{ Sink = function() end },
		{ Sink = function() end }
	}
	local Binding = MultiPropertyBinding():To( Targets )
	Assert.DeepEquals( "Should store the targets", Targets, Binding.Targets )

	Assert.True( "Should remove the first target from the list", Binding:RemoveTarget( Targets[ 1 ] ) )
	Assert.DeepEquals( "Should have only one target left", { Targets[ 2 ] }, Binding.Targets )

	Assert.True( "Should remove the second target from the list", Binding:RemoveTarget( Targets[ 2 ] ) )
	Assert.Equals( "Should be no targets left", 0, #Binding.Targets )
end )

UnitTest:Test( "Should remove itself from sources when destroyed", function( Assert )
	local Source = {
		AddListener = UnitTest.MockFunction(),
		RemoveListener = UnitTest.MockFunction()
	}

	local Binding = MultiPropertyBinding():From( { Source } )
	Binding:Destroy()

	Assert.DeepEquals( "Should remove itself from the source when destroyed", {
		{
			ArgCount = 2,
			Source,
			Binding
		}
	}, Source.RemoveListener.Invocations )

	Binding:Destroy()

	Assert.Equals( "Should not invoke RemoveListener twice when already destroyed", 1, #Source.RemoveListener.Invocations )
end )
