--[[
	Workshop update checker plugin.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = {
	255, 160, 0
}

function Plugin:SetupDataTable()
	local MessageTypes = {
		ModChange = {
			ModName = "string (32)"
		},
		MapCycle = {
			TimeLeft = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.ModChange ] = {
			"MOD_CHANGED"
		},
		[ MessageTypes.MapCycle ] = {
			"MAP_CYCLE"
		}
	} )
end

Shine:RegisterExtension( "workshopupdater", Plugin )
