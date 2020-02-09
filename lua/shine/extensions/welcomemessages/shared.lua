--[[
	Welcome messages plugin.
]]

local Plugin = Shine.Plugin( ... )

function Plugin:SetupDataTable()
	local MessageTypes = {
		GenericWithTeam = {
			TargetName = self:GetNameNetworkField(),
			Team = "integer (0 to 3)"
		},
		Reason = {
			TargetName = self:GetNameNetworkField(),
			Reason = "string (64)",
			Team = "integer (0 to 3)"
		}
	}

	self:AddTranslatedNotifyColour( "PLAYER_JOINED_GENERIC", {
		TargetName = self:GetNameNetworkField()
	} )

	self:AddNetworkMessages( "AddTranslatedRichText", {
		[ MessageTypes.GenericWithTeam ] = {
			"PLAYER_LEAVE_GENERIC"
		},
		[ MessageTypes.Reason ] = {
			"PLAYER_LEAVE_REASON"
		}
	} )
end

return Plugin
