--[[
	Vote surrender client.
]]

local Plugin = ...

function Plugin:NetworkUpdate( Key, Old, New )
	if Key == "ConcedeTime" then
		kMinTimeBeforeConcede = New or kMinTimeBeforeConcede
	end
end

function Plugin:Initialise()
	kMinTimeBeforeConcede = self.dt.ConcedeTime or kMinTimeBeforeConcede

	self.Enabled = true

	return true
end
