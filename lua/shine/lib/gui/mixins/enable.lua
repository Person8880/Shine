--[[
	Provides enabled/disabled states.
]]

local EnableMixin = {}

-- Enabled by default.
EnableMixin.Enabled = true

function EnableMixin:SetEnabled( Enabled )
	self.Enabled = not not Enabled

	if not Enabled then
		self:AddStylingState( "Disabled" )
	else
		self:RemoveStylingState( "Disabled" )
	end
end

function EnableMixin:IsEnabled()
	return self.Enabled
end

Shine.GUI:RegisterMixin( "EnableMixin", EnableMixin )
