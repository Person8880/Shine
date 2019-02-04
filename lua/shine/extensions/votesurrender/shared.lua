--[[
	Vote surrender shared.
]]

local Plugin = Shine.Plugin( ... )
Plugin.EnabledGamemodes = {
	[ "ns2" ] = true,
	[ "mvm" ] = true
}

function Plugin:SetupDataTable()
	self:AddDTVar( "integer", "ConcedeTime", kMinTimeBeforeConcede )
end

return Plugin
