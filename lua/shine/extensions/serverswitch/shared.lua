--[[
	Server switch shared part.
]]

local Plugin = Shine.Plugin( ... )

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "ServerList", {
		Name = "string (15)",
		IP = "string (64)",
		Port = "integer",
		ID = "integer (0 to 255)"
	}, "Client" )
end

return Plugin
