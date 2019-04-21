--[[
	Provides a mechanism to bind properties together.
]]

local MultiPropertyBinding = require "shine/lib/gui/binding/multi_property"
local PropertyBinding = require "shine/lib/gui/binding/property"

local TableShallowMerge = table.ShallowMerge

local Binder = Shine.TypeDef()

function Binder:Init()
	self.Sources = {}
	self.Targets = {}
	return self
end

--[[
	Adds a source property from the given element that will be watched for changes.
]]
function Binder:FromElement( Element, PropertyName )
	self.Sources[ #self.Sources + 1 ] = Element:GetPropertySource( PropertyName )
	return self
end

--[[
	Adds a target property on the given element that will receive changes.

	The parameters argument is an optional table of extra values to configure the target:
		* Transformer - a function that takes the value from the source, and turns it into something else before it is
		  passed into the target property.
		* Filter - a function that decides whether the target should be invoked for a given value from the source.
]]
function Binder:ToElement( Element, PropertyName, Params )
	self.Targets[ #self.Targets + 1 ] = TableShallowMerge( Params or {}, {
		Sink = Element:GetPropertyTarget( PropertyName ),
		Element = Element
	} )
	return self
end

--[[
	Adds a target function to be called when the source value changes.
]]
function Binder:ToListener( Listener, Params )
	self.Targets[ #self.Targets + 1 ] = TableShallowMerge( Params or {}, {
		Sink = Listener
	} )
	return self
end

--[[
	Sets the reducer function (for multiple source property binding).
]]
function Binder:WithReducer( Reducer )
	self.Reducer = Reducer
	return self
end

--[[
	Sets the initial state (for multiple source property binding).
]]
function Binder:WithInitialState( InitialState )
	self.InitialState = InitialState
	return self
end

local function AutoRemoveElements( Binding, Sources, Targets )
	if Binding.RemoveSource then
		for i = 1, #Sources do
			local Source = Sources[ i ]
			if Source.Element and Source.Element.CallOnRemove then
				Source.Element:CallOnRemove( function()
					Binding:RemoveSource( Source )
				end )
			end
		end
	end

	for i = 1, #Targets do
		local Target = Targets[ i ]
		if Target.Element and Target.Element.CallOnRemove then
			Target.Element:CallOnRemove( function()
				Binding:RemoveTarget( Target )
			end )
		end
	end
end

--[[
	Binds the (first) given source to the given targets.

	On destruction of bound target elements, the binding will be automatically updated to remove the destroyed element.
]]
function Binder:BindProperty()
	local Binding = PropertyBinding():From( self.Sources[ 1 ] ):To( self.Targets )
	AutoRemoveElements( Binding, self.Sources, self.Targets )

	-- Trigger the binding to synchronise state.
	Binding:Refresh()

	return Binding
end

--[[
	Binds the given sources to the given targets using the given reducer function.

	On destruction of bound target and source elements, the binding will be automatically updated to remove the
	destroyed element.
]]
function Binder:BindProperties()
	Shine.AssertAtLevel( Shine.IsCallable( self.Reducer ), "Reducer must be provided and callable!", 3 )

	local Binding = MultiPropertyBinding()
		:From( self.Sources )
		:ReducedWith( self.Reducer )
		:WithInitialState( self.InitialState )
		:To( self.Targets )

	AutoRemoveElements( Binding, self.Sources, self.Targets )

	-- Stop if no sources have been setup yet.
	if #self.Sources == 0 then return Binding end

	-- Trigger the binding to synchronise state.
	Binding:Refresh()

	return Binding
end

return Binder
