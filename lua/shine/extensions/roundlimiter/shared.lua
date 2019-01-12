--[[
	Round limiter.
]]

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = {
	100, 255, 100
}

function Plugin:SetupDataTable()
	local MessageTypes = {
		TimeLeft = {
			TimeLeft = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.TimeLeft ] = {
			"ROUND_WARNING_TOTAL_SCORE", "ROUND_WARNING_TOTAL_RTS",
			"ROUND_WARNING_TOTAL_TEAM_RES"
		}
	} )
end

return Plugin
