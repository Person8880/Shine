--[[
	Vote surrender shared.
]]

local Plugin = Shine.Plugin( ... )

function Plugin:SetupDataTable()
	self:AddDTVar( "integer", "ConcedeTime", kMinTimeBeforeConcede )
end

return Plugin
