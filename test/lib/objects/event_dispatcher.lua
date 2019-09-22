--[[
	Event dispatcher tests.
]]

local UnitTest = Shine.UnitTest
local EventDispatcher = Shine.EventDispatcher

UnitTest:Test( "DispatchEvent with no valid listeners", function( Assert )
	local function Fail()
		Assert.Fail( "Listener event called when it shouldn't be!" )
	end
	local Listeners = {
		{
			Cake = Fail
		},
		{
			Cake = Fail
		},
		{
			MoreCake = Fail,
			Cake = Fail
		}
	}

	local Dispatcher = EventDispatcher( Listeners )
	Dispatcher:DispatchEvent( "NoCake", true )
	Assert.IsType( "Should have created a cache for the event name", Dispatcher.ListenersWithEvent.NoCake, "table" )
	Assert.Equals( "Cached listeners should be empty", 0, #Dispatcher.ListenersWithEvent.NoCake )
end )

UnitTest:Test( "DispatchEvent with valid listeners", function( Assert )
	local Called = {}
	local Listeners = {
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 1
			end
		},
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 2
			end
		},
		{
			NoCake = function() Assert.Fail( "Called a method for the wrong event!" ) end
		}
	}

	local Dispatcher = EventDispatcher( Listeners )
	Dispatcher:DispatchEvent( "Cake", false )

	Assert.ArrayEquals( "First 2 listeners should have been called in order", { 1, 2 }, Called )
	Assert.ArrayEquals( "First 2 listeners should be cached as applicable to the event",
		{ Listeners[ 1 ], Listeners[ 2 ] }, Dispatcher.ListenersWithEvent.Cake )
end )

UnitTest:Test( "DispatchEvent with valid listeners returning a value", function( Assert )
	local Called = {}
	local Listeners = {
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 1
				return true
			end
		},
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 2
			end
		},
		{
			NoCake = function() Assert.Fail( "Called a method for the wrong event!" ) end
		}
	}

	local Dispatcher = EventDispatcher( Listeners )
	local Result = Dispatcher:DispatchEvent( "Cake", false )
	Assert.True( "Result expected from DispatchEvent", Result )
	Assert.ArrayEquals( "Only the first listener should have been called due to returned value", { 1 }, Called )
end )

UnitTest:Test( "BroadcastEvent", function( Assert )
	local Called = {}
	local Listeners = {
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 1
				return true
			end
		},
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 2
			end
		},
		{
			NoCake = function() Assert.Fail( "Called a method for the wrong event!" ) end
		}
	}

	local Dispatcher = EventDispatcher( Listeners )
	local Result = Dispatcher:BroadcastEvent( "Cake", false )
	Assert.Nil( "No result expected from BroadcastEvent", Result )
	Assert.ArrayEquals( "Listeners not called in expected order", { 1, 2 }, Called )
end )

local TrackingEventDispatcher = Shine.TrackingEventDispatcher

UnitTest:Test( "TrackingEventDispatcher - DispatchEvent marks events as fired", function( Assert )
	local Called = {}
	local Listeners = {
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 1
				return true
			end
		},
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 2
			end
		},
		{
			NoCake = function() Assert.Fail( "Called a method for the wrong event!" ) end
		}
	}

	local Dispatcher = TrackingEventDispatcher( Listeners )
	Assert.False( "HasFiredEvent should return false for event that hasn't fired", Dispatcher:HasFiredEvent( "Cake" ) )

	local Result = Dispatcher:DispatchEvent( "Cake", false )
	Assert.True( "Result expected from DispatchEvent", Result )
	Assert.ArrayEquals( "Only the first listener should have been called due to returned value", { 1 }, Called )
	Assert.True( "HasFiredEvent should return true for event that has fired", Dispatcher:HasFiredEvent( "Cake" ) )
end )

UnitTest:Test( "TrackingEventDispatcher - BroadcastEvent marks event as fired", function( Assert )
	local Called = {}
	local Listeners = {
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 1
				return true
			end
		},
		{
			Cake = function( self, Value )
				Assert:False( Value )
				Called[ #Called + 1 ] = 2
			end
		},
		{
			NoCake = function() Assert.Fail( "Called a method for the wrong event!" ) end
		}
	}

	local Dispatcher = TrackingEventDispatcher( Listeners )
	Assert.False( "HasFiredEvent should return false for event that hasn't fired", Dispatcher:HasFiredEvent( "Cake" ) )

	local Result = Dispatcher:BroadcastEvent( "Cake", false )
	Assert.Nil( "No result expected from BroadcastEvent", Result )
	Assert.ArrayEquals( "Listeners not called in expected order", { 1, 2 }, Called )
	Assert.True( "HasFiredEvent should return true for event that has fired", Dispatcher:HasFiredEvent( "Cake" ) )
end )
