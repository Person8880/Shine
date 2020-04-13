--[[
	Hook system tests.
]]

local UnitTest = Shine.UnitTest
local Hook = Shine.Hook

local StringFormat = string.format

UnitTest:After( function()
	Hook.Clear( "Test" )
	Hook.Clear( "TestClassTestMethod" )
end )

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

local FunctionName = "TestFunction"..os.time()

UnitTest:Test( "SetupGlobalHook - Replaces functions only once", function( Assert )
	local TestFunction = function() end

	_G[ FunctionName ] = TestFunction

	local OldFunc = Hook.SetupGlobalHook( FunctionName, "Test", "PassivePost" )
	Assert.Equals( "Function returned from SetupGlobalHook should be the global value", TestFunction, OldFunc )

	local NewHookedFunction = _G[ FunctionName ]
	Assert.NotEquals( "Should have replaced the global value", NewHookedFunction, OldFunc )
	Assert.IsType( "Should have replaced the global value with a function", NewHookedFunction, "function" )

	-- Hooking the same function twice with the same hook name and mode should do nothing and return
	-- the original function from the first setup call.
	OldFunc = Hook.SetupGlobalHook( FunctionName, "Test", "PassivePost" )
	Assert.Equals( "Function returned from SetupGlobalHook should still be the global value", TestFunction, OldFunc )
	Assert.Equals( "Global function should be unchanged", NewHookedFunction, _G[ FunctionName ] )

	local Callback = UnitTest.MockFunction()
	Hook.Add( "Test", Callback )

	NewHookedFunction()

	Assert.DeepEquals( "Calling the replaced function should run the hook", {
		{ ArgCount = 0 }
	}, Callback.Invocations )
end )

local NestedName = "TestHolder"..os.time()

UnitTest:Test( "SetupGlobalHook - Handles nested global values", function( Assert )
	local TestFunction = function( Arg1, Arg2, Arg3 ) end
	_G[ NestedName ] = {
		[ FunctionName ] = TestFunction
	}

	-- Having more arguments in the replacement should mean the hooked function has 4 parameters.
	local OldFunc = Hook.SetupGlobalHook( NestedName.."."..FunctionName, "Test", function( OldFunc, Arg1, Arg2, Arg3, Arg4 )
		OldFunc( Arg1, Arg2, Arg3, Arg4 )
		Hook.Broadcast( "Test", Arg1, Arg2, Arg3, Arg4 )
	end )
	Assert.Equals( "Function returned from SetupGlobalHook should be the nested global value", TestFunction, OldFunc )

	local NewHookedFunction = _G[ NestedName ][ FunctionName ]
	Assert.NotEquals( "Should have replaced the nested global value", NewHookedFunction, OldFunc )
	Assert.IsType( "Should have replaced the nested global value with a function", NewHookedFunction, "function" )

	local Callback = UnitTest.MockFunction()
	Hook.Add( "Test", Callback )

	-- Ignores the 5th argument as the number of arguments is the max of the original and replacement.
	NewHookedFunction( 1, 2, 3, 4, 5 )

	Assert.DeepEquals( "Calling the replaced function should run the hook", {
		{ ArgCount = 4, 1, 2, 3, 4 }
	}, Callback.Invocations )
end )

_G[ NestedName ] = nil
_G[ FunctionName ] = nil

local ClassName = "HookTestClass"..os.time()
class( ClassName )

UnitTest:Test( "SetupClassHook - Replaces functions only once", function( Assert )
	local TestFunction = function( self ) end
	_G[ ClassName ].TestMethod = TestFunction

	local function Handler( OldFunc, self, Arg1 )
		OldFunc( self )
		Hook.Broadcast( "TestClassTestMethod", self, Arg1 )
	end
	local OldFunc = Hook.SetupClassHook( ClassName, "TestMethod", "TestClassTestMethod", Handler )
	Assert.Equals( "Function returned from SetupClassHook should be the original method", TestFunction, OldFunc )

	local NewHookedFunction = _G[ ClassName ].TestMethod
	Assert.NotEquals( "Should have replaced the class method", NewHookedFunction, OldFunc )
	Assert.IsType( "Should have replaced the class method with a function", NewHookedFunction, "function" )

	-- Hooking the same function twice with the same hook name and mode should do nothing and return
	-- the original function from the first setup call.
	OldFunc = Hook.SetupClassHook( ClassName, "TestMethod", "TestClassTestMethod", Handler )
	Assert.Equals( "Function returned from SetupClassHook should still be the original method", TestFunction, OldFunc )
	Assert.Equals( "Class method should be unchanged", NewHookedFunction, _G[ ClassName ].TestMethod )

	local Callback = UnitTest.MockFunction()
	Hook.Add( "TestClassTestMethod", Callback )

	-- Should pass through 2 arguments, as that's the max of the original and replacement functions.
	local Arg = {}
	NewHookedFunction( Arg, 1, 2 )

	Assert.DeepEquals( "Calling the replaced function should run the hook", {
		{ ArgCount = 2, Arg, 1 }
	}, Callback.Invocations )
end )

local HOOK_RETURN_VALUE = "HOOK_RETURN_VALUE"
local ORIGINAL_RETURN_VALUE = "ORIGINAL_RETURN_VALUE"

local HookModeTests = {
	{
		Mode = "Replace",

		ShouldCallOriginalOnHookReturn = false,
		ExpectedOnHookReturn = HOOK_RETURN_VALUE,

		ShouldCallOriginalOnHookNil = false,
		ExpectedOnHookNil = nil
	},
	{
		Mode = "PassivePre",

		ShouldCallOriginalOnHookReturn = true,
		ExpectedOnHookReturn = ORIGINAL_RETURN_VALUE,

		ShouldCallOriginalOnHookNil = true,
		ExpectedOnHookNil = ORIGINAL_RETURN_VALUE
	},
	{
		Mode = "PassivePost",

		ShouldCallOriginalOnHookReturn = true,
		ExpectedOnHookReturn = ORIGINAL_RETURN_VALUE,

		ShouldCallOriginalOnHookNil = true,
		ExpectedOnHookNil = ORIGINAL_RETURN_VALUE
	},
	{
		Mode = "ActivePre",

		ShouldCallOriginalOnHookReturn = false,
		ExpectedOnHookReturn = HOOK_RETURN_VALUE,

		ShouldCallOriginalOnHookNil = true,
		ExpectedOnHookNil = ORIGINAL_RETURN_VALUE
	},
	{
		Mode = "ActivePost",

		ShouldCallOriginalOnHookReturn = true,
		ExpectedOnHookReturn = HOOK_RETURN_VALUE,

		ShouldCallOriginalOnHookNil = true,
		ExpectedOnHookNil = ORIGINAL_RETURN_VALUE
	},
	{
		Mode = "Halt",

		ShouldCallOriginalOnHookReturn = false,
		ExpectedOnHookReturn = nil,

		ShouldCallOriginalOnHookNil = true,
		ExpectedOnHookNil = ORIGINAL_RETURN_VALUE
	}
}

local OriginalFunction = UnitTest.MockFunction( function() return ORIGINAL_RETURN_VALUE end )
UnitTest:Before( function()
	OriginalFunction:Reset()
end )

for i = 1, #HookModeTests do
	local TestCase = HookModeTests[ i ]
	local GlobalKey = FunctionName..TestCase.Mode
	local GlobalHookName = "TestGlobalHook"..TestCase.Mode

	_G[ GlobalKey ] = OriginalFunction
	Hook.SetupGlobalHook( GlobalKey, GlobalHookName, TestCase.Mode )

	UnitTest:Test(
		StringFormat(
			"SetupGlobalHook - Applies a %s hook mode as expected when the hook returns a value",
			TestCase.Mode
		),
		function( Assert )
			Assert.NotEquals( "Should have replaced the global value", OriginalFunction, _G[ GlobalKey ] )

			Hook.Add( GlobalHookName, "TestCase", function() return HOOK_RETURN_VALUE end )
			Assert.Equals(
				"Should return the expected value when the hook returns a value",
				TestCase.ExpectedOnHookReturn,
				_G[ GlobalKey ]()
			)

			if TestCase.ShouldCallOriginalOnHookReturn then
				Assert.Equals( "Should have called the original function", 1, OriginalFunction:GetInvocationCount() )
			else
				Assert.Equals(
					"Should not have called the original function", 0, OriginalFunction:GetInvocationCount()
				)
			end
		end
	)

	UnitTest:Test(
		StringFormat(
			"SetupGlobalHook - Applies a %s hook mode as expected when the hook returns nil",
			TestCase.Mode
		),
		function( Assert )
			Hook.Add( GlobalHookName, "TestCase", function() return nil end )
			Assert.Equals(
				"Should return the expected value when the hook returns nil",
				TestCase.ExpectedOnHookNil,
				_G[ GlobalKey ]()
			)
			if TestCase.ShouldCallOriginalOnHookNil then
				Assert.Equals( "Should have called the original function", 1, OriginalFunction:GetInvocationCount() )
			else
				Assert.Equals(
					"Should not have called the original function", 0, OriginalFunction:GetInvocationCount()
				)
			end
		end
	)

	Hook.Clear( GlobalHookName )

	_G[ GlobalKey ] = nil

	local ClassKey = TestCase.Mode
	local ClassHookName = "TestClassHook"..TestCase.Mode

	_G[ ClassName ][ ClassKey ] = OriginalFunction
	Hook.SetupClassHook( ClassName, ClassKey, ClassHookName, TestCase.Mode )

	UnitTest:Test(
		StringFormat(
			"SetupClassHook - Applies a %s hook mode as expected when the hook returns a value",
			TestCase.Mode
		),
		function( Assert )
			Assert.NotEquals( "Should have replaced the class method", OriginalFunction, _G[ ClassName ][ ClassKey ] )

			Hook.Add( ClassHookName, "TestCase", function() return HOOK_RETURN_VALUE end )
			Assert.Equals(
				"Should return the expected value when the hook returns a value",
				TestCase.ExpectedOnHookReturn,
				_G[ ClassName ][ ClassKey ]()
			)

			if TestCase.ShouldCallOriginalOnHookReturn then
				Assert.Equals( "Should have called the original function", 1, OriginalFunction:GetInvocationCount() )
			else
				Assert.Equals(
					"Should not have called the original function", 0, OriginalFunction:GetInvocationCount()
				)
			end
		end
	)

	UnitTest:Test(
		StringFormat(
			"SetupClassHook - Applies a %s hook mode as expected when the hook returns nil",
			TestCase.Mode
		),
		function( Assert )
			Hook.Add( ClassHookName, "TestCase", function() return nil end )
			Assert.Equals(
				"Should return the expected value when the hook returns nil",
				TestCase.ExpectedOnHookNil,
				_G[ ClassName ][ ClassKey ]()
			)
			if TestCase.ShouldCallOriginalOnHookNil then
				Assert.Equals( "Should have called the original function", 1, OriginalFunction:GetInvocationCount() )
			else
				Assert.Equals(
					"Should not have called the original function", 0, OriginalFunction:GetInvocationCount()
				)
			end
		end
	)

	Hook.Clear( ClassHookName )
end

_G[ ClassName ] = nil
