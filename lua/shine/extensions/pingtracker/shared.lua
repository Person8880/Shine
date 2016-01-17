--[[
	Ping tracker shared.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = {
	255, 160, 0
}

function Plugin:SetupDataTable()
	local MessageTypes = {
		Latency = {
			Amount = "integer (0 to 2000)"
		}
	}
	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.Latency ] = {
			"PING_TOO_HIGH", "JITTER_TOO_HIGH"
		}
	} )
end

Shine:RegisterExtension( "pingtracker", Plugin )
