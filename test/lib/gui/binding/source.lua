--[[
	Source tests.
]]

local UnitTest = Shine.UnitTest
local Source = require "shine/lib/gui/binding/source"

UnitTest:Test( "It should add/remove/call listeners as expected", function( Assert )
	local Listener1 = UnitTest.MockFunction( function( Source, Value )
		Assert.Equals( "Source value should be updated before invoking", Value, Source:GetValue() )
	end )
	local Listener2 = UnitTest.MockFunction()

	local Host = {}
	local SourceInstance = Source()
	SourceInstance:AddListener( Listener1 )
	SourceInstance:AddListener( Listener2 )

	SourceInstance( Host, "test" )

	SourceInstance:RemoveListener( Listener2 )

	SourceInstance( Host, "test2" )

	Assert.DeepEquals( "Should have called the first listener twice", {
		{
			ArgCount = 2,
			SourceInstance,
			"test"
		},
		{
			ArgCount = 2,
			SourceInstance,
			"test2"
		}
	}, Listener1.Invocations )
	Assert.DeepEquals( "Should have called the second listener once", {
		{
			ArgCount = 2,
			SourceInstance,
			"test"
		}
	}, Listener2.Invocations )
end )
