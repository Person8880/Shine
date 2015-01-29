--[[
	Shine voting radial menu.
]]

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
Shared.RegisterNetworkMessage( "Shine_AuthAdminMenu", {} )
