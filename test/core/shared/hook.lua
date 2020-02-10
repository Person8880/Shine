--[[
	Hook system tests.
]]

local UnitTest = Shine.UnitTest
local Hook = Shine.Hook

local function TestHooks( Assert, MethodName )
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
		Hook[ MethodName ]( "Test" )

		Assert.ArrayEquals( "Unexpected hook calls after Hook."..MethodName, Expected, Called )

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
end

UnitTest:Test( "Hook integration test", function( Assert )
	TestHooks( Assert, "Call" )
	TestHooks( Assert, "Broadcast" )
end )

Hook.Clear( "Test" )

UnitTest:Test( "Broadcast - Ignores return values", function( Assert )
	local Called = {}
	Hook.Add( "Test", "ReturnsValue", function()
		Called[ #Called + 1 ] = "ReturnsValue"
		return true
	end, Hook.MAX_PRIORITY )
	Hook.Add( "Test", "DoesNotReturnValue", function()
		Called[ #Called + 1 ] = "DoesNotReturnValue"
	end )

	Hook.Broadcast( "Test" )

	Assert.ArrayEquals( "Should have called both listeners", { "ReturnsValue", "DoesNotReturnValue" }, Called )
end )

Hook.Clear( "Test" )

local FunctionName = "TestFunction"..os.time()

UnitTest:Test( "SetupGlobalHook replaces functions only once", function( Assert )
	local TestFunction = function() end

	_G[ FunctionName ] = TestFunction

	local OldFunc = Hook.SetupGlobalHook( FunctionName, "Test", "PassivePost" )
	Assert.Equals( "Function returned from SetupGlobalHook should be the global value", TestFunction, OldFunc )

	local NewHookedFunction = _G[ FunctionName ]

	-- Hooking the same function twice with the same hook name and mode should do nothing and return
	-- the original function from the first setup call.
	OldFunc = Hook.SetupGlobalHook( FunctionName, "Test", "PassivePost" )
	Assert.Equals( "Function returned from SetupGlobalHook should still be the global value", TestFunction, OldFunc )
	Assert.Equals( "Global function should be unchanged", NewHookedFunction, _G[ FunctionName ] )
end )

_G[ FunctionName ] = nil

local ClassName = "HookTestClass"..os.time()

UnitTest:Test( "SetupClassHook replaces functions only once", function( Assert )
	class( ClassName )

	local TestFunction = function() end
	_G[ ClassName ].TestMethod = TestFunction

	local OldFunc = Hook.SetupClassHook( ClassName, "TestMethod", "TestClassTestMethod", "PassivePost" )
	Assert.Equals( "Function returned from SetupClassHook should be the original method", TestFunction, OldFunc )

	local NewHookedFunction = _G[ ClassName ].TestMethod

	-- Hooking the same function twice with the same hook name and mode should do nothing and return
	-- the original function from the first setup call.
	OldFunc = Hook.SetupClassHook( ClassName, "TestMethod", "TestClassTestMethod", "PassivePost" )
	Assert.Equals( "Function returned from SetupClassHook should still be the original method", TestFunction, OldFunc )
	Assert.Equals( "Class method should be unchanged", NewHookedFunction, _G[ ClassName ].TestMethod )
end )

_G[ ClassName ] = nil
