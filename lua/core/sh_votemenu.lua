--[[
	Shine voting radial menu.
]]

Shine = Shine or {}

local NWMessage = {
	Options = "string (255)",
	Duration = "integer (0 to 1800)",
	NextMap = "integer (0 to 1)"
}

Shared.RegisterNetworkMessage( "Shine_VoteMenu", NWMessage )

local PluginMessage = {
	Random = "integer (0 to 1)",
	RTV = "integer (0 to 1)",
	Scramble = "integer (0 to 1)",
	Surrender = "integer (0 to 1)",
	Unstuck = "integer (0 to 1)",
	MOTD = "integer (0 to 1)"
}

Shared.RegisterNetworkMessage( "Shine_PluginData", PluginMessage )