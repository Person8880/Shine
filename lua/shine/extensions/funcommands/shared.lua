--[[
	Fun commands shared.
]]

local Plugin = Shine.Plugin( ... )

Plugin.TeleportMessageKeys = {
	"TELEPORTED_GOTO",
	"TELEPORTED_BRING"
}
Plugin.ActionMessageKeys = {
	"SLAYED",
	"GRANTED_DARWIN_MODE",
	"REVOKED_DARWIN_MODE"
}

function Plugin:SetupDataTable()
	local TeleportMessage = {
		TargetName = self:GetNameNetworkField()
	}
	local TeleportToLocationMessage = {
		LocationID = "integer"
	}
	local TeleportTargetToLocationMessage = {
		TargetName = TeleportMessage.TargetName,
		LocationID = TeleportToLocationMessage.LocationID
	}
	local TeleportSendToMessage = {
		SourceName = TeleportMessage.TargetName,
		TargetName = TeleportMessage.TargetName
	}
	local TargetCountMessage = {
		TargetCount = "integer (0 to 127)"
	}
	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ TeleportMessage ] = self.TeleportMessageKeys,
		[ TargetCountMessage ] = self.ActionMessageKeys,
		[ TeleportToLocationMessage ] = {
			"TELEPORTED_GOTO_LOCATION"
		},
		[ TeleportTargetToLocationMessage ] = {
			"TELEPORTED_SENT_TO_LOCATION"
		},
		[ TeleportSendToMessage ] = {
			"TELEPORTED_SENT_TO"
		}
	} )
end

return Plugin
