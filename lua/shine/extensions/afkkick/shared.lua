--[[
	AFK plugin shared.
]]

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = { 255, 50, 0 }

Plugin.AFK_PREFIX = "AFK - "

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "AFKNotify", {}, "Client" )
	self:AddTranslatedNotify( "WARN_KICK_ON_CONNECT", {
		AFKTime = "integer"
	} )
	self:AddTranslatedNotify( "WARN_WILL_BE_KICKED", {
		AFKTime = "integer",
		KickTime = "integer"
	} )
	self:AddTranslatedNotify( "WARN_NOTIFY", {
		AFKTime = "integer",
		KickTime = "integer",
		MinPlayers = "integer"
	} )
end

Shine.UpdateClassNetVars( "PlayerInfoEntity", "lua/PlayerInfoEntity.lua", {
	afk = "boolean"
} )

return Plugin
