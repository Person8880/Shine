--[[
	Provides enabled/disabled states.
]]

local EnableMixin = {}

-- Enabled by default.
EnableMixin.Enabled = true

function EnableMixin:SetEnabled( Enabled )
	self.Enabled = Enabled
	self:SetStylingState( Enabled and "Enabled" or "Disabled" )
end

function EnableMixin:IsEnabled()
	return self.Enabled
end

Shine.GUI:RegisterMixin( "EnableMixin", EnableMixin )
