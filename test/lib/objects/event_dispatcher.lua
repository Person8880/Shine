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
	Assert:IsType( Dispatcher.ListenersWithEvent.NoCake, "table" )
	Assert:Equals( 0, #Dispatcher.ListenersWithEvent.NoCake )
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

	Assert:ArrayEquals( { 1, 2 }, Called )
	Assert:ArrayEquals( { Listeners[ 1 ], Listeners[ 2 ] }, Dispatcher.ListenersWithEvent.Cake )
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
	Assert:True( Result )
	Assert:ArrayEquals( { 1 }, Called )
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
	Assert:Nil( Result )
	Assert:ArrayEquals( { 1, 2 }, Called )
end )
