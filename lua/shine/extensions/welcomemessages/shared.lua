--[[
	Welcome messages plugin.
]]

local Plugin = Shine.Plugin( ... )

function Plugin:SetupDataTable()
	local MessageTypes = {
		Generic = {
			TargetName = self:GetNameNetworkField()
		},
		Reason = {
			TargetName = self:GetNameNetworkField(),
			Reason = "string (64)"
		}
	}

	self:AddNetworkMessages( "AddTranslatedNotifyColour", {
		[ MessageTypes.Generic ] = {
			"PLAYER_JOINED_GENERIC", "PLAYER_LEAVE_GENERIC"
		},
		[ MessageTypes.Reason ] = {
			"PLAYER_LEAVE_REASON"
		}
	} )
end

return Plugin
