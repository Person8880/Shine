--[[
	Provides enabled/disabled states.
]]

local EnableMixin = {}

-- Enabled by default.
EnableMixin.Enabled = true

function EnableMixin:SetEnabled( Enabled )
	Enabled = not not Enabled

	if self.Enabled == Enabled then return end

	self.Enabled = Enabled

	if not Enabled then
		self:AddStylingState( "Disabled" )
	else
		self:RemoveStylingState( "Disabled" )
	end

	self:OnPropertyChanged( "Enabled", Enabled )
end

function EnableMixin:IsEnabled()
	return self.Enabled
end

Shine.GUI:RegisterMixin( "EnableMixin", EnableMixin )
