--[[
	Timer tests.
]]

local Time = 0
local Env = setmetatable( {
	Shine = setmetatable( {
		Hook = {
			Add = function() end
		}
	}, { __index = Shine } ),
	Shared = {
		GetTime = function() return Time end
	}
}, { __index = _G } )

-- Load a copy of the timer system to avoid interacting with real timers.
local Func = assert( loadfile( "lua/shine/lib/timer.lua" ) )
setfenv( Func, Env )

Func()

local Timer = Env.Shine.Timer
local UnitTest = Shine.UnitTest

local function AdvanceTime( Amount )
	Time = Time + Amount
	Timer.__ProcessTimers( Time )
end

UnitTest:Test( "SimpleTimer fires after given delay once", function( Assert )
	local Callback = UnitTest.MockFunction()
	local SimpleTimer = Timer.Simple( 5, Callback )
	Assert.True( "Should have added the timer", Timer.Exists( SimpleTimer.Name ) )

	AdvanceTime( 1 )
	Assert.CalledTimes( "Should not have called the timer yet", Callback, 0 )

	AdvanceTime( 4 )
	Assert.Called( "Should have called the timer after its delay", Callback, SimpleTimer )
	Assert.False( "Should have removed the timer after calling it", Timer.Exists( SimpleTimer.Name ) )

	AdvanceTime( 1 )
	Assert.CalledTimes( "Should not have called the timer again", Callback, 1 )
end )

UnitTest:Test( "Timer removal mid-iteration should be handled", function( Assert )
	local Timer1Callback = UnitTest.MockFunction( function() Timer.Destroy( "Test2" ) end )
	local Timer2Callback = UnitTest.MockFunction()
	local Timer3Callback = UnitTest.MockFunction()

	local Timer1 = Timer.Create( "Test1", 5, 2, Timer1Callback )
	Timer.Create( "Test2", 5, 2, Timer2Callback )
	local Timer3 = Timer.Create( "Test3", 5, 2, Timer3Callback )

	AdvanceTime( 5 )

	Assert.Called( "Should have called the first timer", Timer1Callback, Timer1 )
	Assert.CalledTimes( "Should not have called the second timer", Timer2Callback, 0 )
	Assert.False( "Second timer should have been destroyed", Timer.Exists( "Test2" ) )
	Assert.Called( "Should have called the third timer", Timer3Callback, Timer3 )

	AdvanceTime( 5 )

	Assert.CalledTimes( "Should have called the first timer again", Timer1Callback, 2 )
	Assert.CalledTimes( "Should still not have called the second timer", Timer2Callback, 0 )
	Assert.CalledTimes( "Should have called the third timer again", Timer3Callback, 2 )
	Assert.False( "First timer should have run out of repetitions", Timer.Exists( "Test1" ) )
	Assert.False( "Third timer should have run out of repetitions", Timer.Exists( "Test3" ) )
end )

UnitTest:Test( "Timer pause mid-iteration should be handled", function( Assert )
	local Timer1Callback = UnitTest.MockFunction( function() Timer.Pause( "Test2" ) end )
	local Timer2Callback = UnitTest.MockFunction()

	local Timer1 = Timer.Create( "Test1", 5, 2, Timer1Callback )
	Timer.Create( "Test2", 5, 2, Timer2Callback )

	AdvanceTime( 5 )

	Assert.Called( "Should have called the first timer", Timer1Callback, Timer1 )
	Assert.CalledTimes( "Should not have called the second timer", Timer2Callback, 0 )
	Assert.True( "Second timer should still exist", Timer.Exists( "Test2" ) )

	local Timer2 = Timer.Get( "Test2" )
	Assert.NotNil( "Second timer should be retrievable", Timer2 )
	Assert.True( "Second timer should be paused", Timer2.Paused )

	AdvanceTime( 5 )

	Assert.CalledTimes( "Should have called the first timer again", Timer1Callback, 2 )
	Assert.CalledTimes( "Should still not have called the second timer", Timer2Callback, 0 )
	Assert.False( "First timer should have run out of repetitions", Timer.Exists( "Test1" ) )

	AdvanceTime( 5 )

	Assert.CalledTimes( "Should not have called the first timer again", Timer1Callback, 2 )
	Assert.CalledTimes( "Should still not have called the second timer", Timer2Callback, 0 )

	Timer.Resume( "Test2" )
	Assert.Falsy( "Second timer should no longer be paused", Timer2.Paused )
	Assert.True( "Second timer should still exist", Timer.Exists( "Test2" ) )

	Timer1Callback = UnitTest.MockFunction()
	Timer1 = Timer.Create( "Test1", 5, 2, Timer1Callback )

	AdvanceTime( 5 )

	Assert.Called( "Should have called the first timer again", Timer1Callback, Timer1 )
	Assert.Called( "Should have called the second timer", Timer2Callback, Timer2 )

	AdvanceTime( 5 )

	Assert.CalledTimes( "Should have called the first timer again", Timer1Callback, 2 )
	Assert.CalledTimes( "Should have called the second timer again", Timer2Callback, 2 )

	AdvanceTime( 5 )

	Assert.CalledTimes( "Should not have called the first timer again", Timer1Callback, 2 )
	Assert.False( "First timer should have run out of repetitions", Timer.Exists( "Test1" ) )
	Assert.CalledTimes( "Should not have called the second timer again", Timer2Callback, 2 )
	Assert.False( "Second timer should have run out of repetitions", Timer.Exists( "Test2" ) )
end )
