--[[
	Provides enabled/disabled states.
]]

local EnableMixin = {}

-- Enabled by default.
EnableMixin.Enabled = true

function EnableMixin:SetEnabled( Enabled )
	self.Enabled = Enabled and true or false

	local State = nil
	if not Enabled then
		State = "Disabled"
	end
	self:SetStylingState( State )
end

function EnableMixin:IsEnabled()
	return self.Enabled
end

Shine.GUI:RegisterMixin( "EnableMixin", EnableMixin )
