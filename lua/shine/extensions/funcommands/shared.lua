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
	local TargetCountMessage = {
		TargetCount = "integer (0 to 127)"
	}
	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ TeleportMessage ] = self.TeleportMessageKeys,
		[ TargetCountMessage ] = self.ActionMessageKeys
	} )
end

return Plugin
