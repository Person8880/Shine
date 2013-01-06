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