--[[
	Admin menu shared.
]]

Shared.RegisterNetworkMessage( "Shine_AdminMenu_Open", {} )

if Client then return end

Shine:RegisterCommand( "sh_adminmenu", "menu", function( Client )
	Server.SendNetworkMessage( Client, "Shine_AdminMenu_Open", {}, true )
end )
