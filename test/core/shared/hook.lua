--[[
	Hook system tests.
]]

local UnitTest = Shine.UnitTest
local Hook = Shine.Hook

UnitTest:Test( "Hook integration test", function( Assert )
	local Called = {}
	Hook.Add( "Test", "Normal1", function()
		Called[ #Called + 1 ] = "Normal1"
	end )
	Hook.Add( "Test", "Normal2", function()
		Hook.Remove( "Test", "Normal1" )
		Hook.Remove( "Test", "LowPriority" )
		Hook.Remove( "Test", "Normal2" )
		Called[ #Called + 1 ] = "Normal2"
	end )
	Hook.Add( "Test", "Normal3", function()
		Called[ #Called + 1 ] = "Normal3"
	end )
	Hook.Add( "Test", "CalledFirst", function()
		Called[ #Called + 1 ] = "CalledFirst"
	end, Hook.MAX_PRIORITY )
	Hook.Add( "Test", "CalledLast", function()
		Called[ #Called + 1 ] = "CalledLast"
	end, Hook.MIN_PRIORITY )
	Hook.Add( "Test", "LowPriority", function()
		Called[ #Called + 1 ] = "LowPriority"
	end, Hook.DEFAULT_PRIORITY + 5 )

	local function AssertCallOrder( Expected )
		Hook.Call( "Test" )

		Assert.ArrayEquals( "Unexpected hook calls", Expected, Called )

		Called = {}
	end

	-- Call in priority order, with equal priority using insertion order.
	-- Normal2 will remove itself, the low priority hook and the hook before it.
	AssertCallOrder{
		"CalledFirst", "Normal1", "Normal2", "Normal3", "CalledLast"
	}
	-- This results in a second call omitting the removed callbacks.
	AssertCallOrder{ "CalledFirst", "Normal3", "CalledLast" }

	-- When a hook adds more hooks, they should be called if ordered later.
	Hook.Add( "Test", "Normal1", function()
		Hook.Add( "Test", "Normal2", function()
			Called[ #Called + 1 ] = "Normal2"
		end )
		Hook.Add( "Test", "CalledSecond", function()
			Called[ #Called + 1 ] = "CalledSecond"
		end, Hook.MAX_PRIORITY + 1 )
		Called[ #Called + 1 ] = "Normal1"
	end )

	-- Normal3 exists from before, Normal1 adds a few new callbacks (of which only Normal2 is after it).
	AssertCallOrder{ "CalledFirst", "Normal3", "Normal1", "Normal2", "CalledLast" }
	-- The final call will include the -10 priority callback but keep the same hooks as the identifiers are equal.
	AssertCallOrder{ "CalledFirst", "CalledSecond", "Normal3", "Normal1", "Normal2", "CalledLast" }

	Hook.Clear( "Test" )

	-- Nothing should be called after clearing.
	AssertCallOrder{}
end )

Hook.Clear( "Test" )
