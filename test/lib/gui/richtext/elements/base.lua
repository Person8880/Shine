--[[
	Tests for base rich text element.
]]

local UnitTest = Shine.UnitTest
local Base = require "shine/lib/gui/richtext/elements/base"

UnitTest:Test( "AddThinkFunction - Adds the given callback", function( Assert )
	local MetaTable = {
		__index = {
			Think = UnitTest.MockFunction()
		}
	}
	local Element = setmetatable( {}, MetaTable )

	local Think = UnitTest.MockFunction()
	Base.AddThinkFunction( Element, Think )

	Assert.IsType( "Should have set a function value to Think", Element.Think, "function" )

	Element:Think( 0 )

	Assert.DeepEquals( "Should have invoked the added think function", {
		{
			ArgCount = 2,
			Element,
			0
		}
	}, Think.Invocations )
	Assert.DeepEquals( "Should have invoked the original think function", {
		{
			ArgCount = 2,
			Element,
			0
		}
	}, MetaTable.__index.Think.Invocations )
end )

UnitTest:Test( "AddThinkFunction - Removes any existing override if passed nil", function( Assert )
	local MetaTable = {
		__index = {
			Think = function() end
		}
	}
	local Element = setmetatable( {
		Think = function() end,
		__ExtraThink = UnitTest.MockFunction(),
		__OldThink = UnitTest.MockFunction()
	}, MetaTable )

	Base.AddThinkFunction( Element, nil )

	Assert.Nil( "Should have removed the extra think field", Element.__ExtraThink )
	Assert.Nil( "Should have removed the old think field", Element.__OldThink )
	Assert.Equals( "Should have restored the original Think function", MetaTable.__index.Think, Element.Think )
end )
