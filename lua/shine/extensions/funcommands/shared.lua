--[[
	Fun commands shared.
]]

local Plugin = Shine.Plugin( ... )

function Plugin:SetupDataTable()
	local TeleportMessage = {
		TargetName = self:GetNameNetworkField()
	}
	local TargetCountMessage = {
		TargetCount = "integer (0 to 127)"
	}
	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ TeleportMessage ] = {
			"TELEPORTED_GOTO", "TELEPORTED_BRING"
		},
		[ TargetCountMessage ] = {
			"SLAYED", "GRANTED_DARWIN_MODE", "REVOKED_DARWIN_MODE"
		}
	} )
end

return Plugin
