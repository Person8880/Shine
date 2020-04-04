--[[
	Event dispatchers provide an optimal way of calling an event
	on a list of tables which may or may not have a callback for it.
]]

local CodeGen = require "shine/lib/codegen"

local IsType = Shine.IsType
local select = select
local TableEmpty = table.Empty

local EventDispatcher = Shine.TypeDef()
Shine.EventDispatcher = EventDispatcher

function EventDispatcher:Init( EventListeners )
	self.EventListeners = EventListeners
	self.ListenersWithEvent = {}

	return self
end

function EventDispatcher:FlushCache()
	self.ListenersWithEvent = {}
end

--[[
	Default behaviour just calls the method.

	May wish to override with a protected call and error handling.
]]
function EventDispatcher:CallEvent( Listener, Method, ... )
	return Method( Listener, ... )
end

--[[
	Default behaviour determines any table with a function under the event name
	is a valid event listener.
]]
function EventDispatcher:IsListenerValidForEvent( Listener, Event )
	return IsType( Listener[ Event ], "function" )
end

--[[
	Default behaviour takes the value in the table as the listener.
]]
function EventDispatcher:GetListener( ListenerEntry )
	return ListenerEntry
end

--[[
	Retrieves all listeners in the listener list that are listening for the
	given event. This is then cached so that only those listeners are called
	for the given event.
]]
function EventDispatcher:GetListenersForEvent( Event )
	local Listeners = self.ListenersWithEvent[ Event ]
	if Listeners then return Listeners end

	local Count = 0
	Listeners = {}

	for i = 1, #self.EventListeners do
		local Listener = self:GetListener( self.EventListeners[ i ] )
		if self:IsListenerValidForEvent( Listener, Event ) then
			Count = Count + 1
			Listeners[ Count ] = Listener
		end
	end

	Listeners.Count = Count
	self.ListenersWithEvent[ Event ] = Listeners

	return Listeners
end

local Dispatchers = CodeGen.MakeFunctionGenerator( {
	Template = [[return function( self, Event{Arguments} )
			local Listeners = self:GetListenersForEvent( Event )
			for i = 1, Listeners.Count do
				local a, b, c, d, e, f = self:CallEvent( Listeners[ i ], Listeners[ i ][ Event ]{Arguments} )
				if a ~= nil then
					return a, b, c, d, e, f
				end
			end
		end
	]],
	ChunkName = "@lua/shine/lib/objects/event_dispatcher.lua/DispatchEvent",
	InitialSize = 12
} )

--[[
	Dispatches an event to all listeners that are listening for it.

	Only checks the listeners once to determine which (if any) are listening for the event.
	Subsequent calls use the cached list until the cache is flushed.
]]
function EventDispatcher:DispatchEvent( Event, ... )
	return Dispatchers[ select( "#", ... ) ]( self, Event, ... )
end

local Broadcasters = CodeGen.MakeFunctionGenerator( {
	Template = [[return function( self, Event{Arguments} )
			local Listeners = self:GetListenersForEvent( Event )
			for i = 1, Listeners.Count do
				self:CallEvent( Listeners[ i ], Listeners[ i ][ Event ]{Arguments} )
			end
		end
	]],
	ChunkName = "@lua/shine/lib/objects/event_dispatcher.lua/BroadcastEvent",
	InitialSize = 12
} )

--[[
	Broadcasts an event to all listeners that are listening for it.

	Unlike DispatchEvent, listeners returning values does not stop the event
	from continuing. All listeners are guaranteed to receive the event.
]]
function EventDispatcher:BroadcastEvent( Event, ... )
	return Broadcasters[ select( "#", ... ) ]( self, Event, ... )
end

--[[
	A sub class of EventDispatcher that tracks events that have been called.
]]
local TrackingEventDispatcher = Shine.TypeDef( EventDispatcher )
Shine.TrackingEventDispatcher = TrackingEventDispatcher

function TrackingEventDispatcher:Init( EventListeners )
	self.FiredEvents = {}
	return EventDispatcher.Init( self, EventListeners )
end

function TrackingEventDispatcher:ResetHistory()
	TableEmpty( self.FiredEvents )
end

function TrackingEventDispatcher:BroadcastEvent( Event, ... )
	self.FiredEvents[ Event ] = true
	return EventDispatcher.BroadcastEvent( self, Event, ... )
end

function TrackingEventDispatcher:DispatchEvent( Event, ... )
	self.FiredEvents[ Event ] = true
	return EventDispatcher.DispatchEvent( self, Event, ... )
end

function TrackingEventDispatcher:HasFiredEvent( Event )
	return not not self.FiredEvents[ Event ]
end
