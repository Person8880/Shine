--[[
	Represents a property source.

	Holds a current value, is called when a change occurs, and broadcasts
	changes to listeners.
]]

local Source = Shine.TypeDef()

function Source:Init( Value )
	self.Listeners = Shine.Set()
	self.Value = Value
	return self
end

function Source:GetValue()
	return self.Value
end

function Source:AddListener( Listener )
	self.Listeners:Add( Listener )
	return self
end

function Source:RemoveListener( Listener )
	self.Listeners:Remove( Listener )
	return self
end

-- Called when a change occurs, internally tracks whether a value has changed
-- and then calls downstream listeners if it has.
function Source:__call( _, Value )
	if self.Value == Value then return end

	-- Update the value before calling listeners to allow them to iterate over
	-- multiple sources to reduce down to a single value.
	self.Value = Value

	for Listener in self.Listeners:Iterate() do
		Listener( self, Value )
	end
end

return Source
