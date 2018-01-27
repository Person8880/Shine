--[[
	Unstuck plugin.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = {
	0, 255, 0
}

function Plugin:SetupDataTable()
	local MessageTypes = {
		TimeLeft = {
			TimeLeft = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.TimeLeft ] = {
			"ERROR_WAIT", "ERROR_FAIL"
		}
	} )
	self:AddTranslatedNotify( "UNSTICKING", MessageTypes.TimeLeft )
end

Shine:RegisterExtension( "unstuck", Plugin )
