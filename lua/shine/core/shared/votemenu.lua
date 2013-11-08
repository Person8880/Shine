--[[
	Shine voting radial menu.
]]

Shine = Shine or {}

Shared.RegisterNetworkMessage( "Shine_OpenedVoteMenu", {} )

local PluginMessage = {
	Shuffle = "boolean",
	RTV = "boolean",
	Surrender = "boolean",
	Unstuck = "boolean",
	MOTD = "boolean"
}

Shared.RegisterNetworkMessage( "Shine_PluginData", PluginMessage )

Shared.RegisterNetworkMessage( "Shine_RequestPluginData", {} )
