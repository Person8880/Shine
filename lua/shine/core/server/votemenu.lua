--[[
	Shine voting radial menu server side.
]]

local function BuildPluginData( self )
	local Plugins = self.Plugins

	return {
		Shuffle = self:IsExtensionEnabled( "voterandom" ),
		[ "Map Vote" ] = self:IsExtensionEnabled( "mapvote" ) and Plugins.mapvote.Config.EnableRTV or false,
		Surrender = self:IsExtensionEnabled( "votesurrender" ),
		Unstuck = self:IsExtensionEnabled( "unstuck" ),
		MOTD = self:IsExtensionEnabled( "motd" )
	}
end

function Shine:SendPluginData( Player )
	self:ApplyNetworkMessage( Player, "Shine_PluginData", BuildPluginData( self ), true )
end

do
	local AuthedWithAdminMenu = Shine.Set()
	local function SendClientAdminMenuAccess( Client, CanUseAdminMenu )
		Shine.SendNetworkMessage( Client, "Shine_AuthAdminMenu", {
			CanUseAdminMenu = CanUseAdminMenu
		}, true )
	end

	-- Send plugin data + admin menu auth state on client connect.
	Shine.Hook.Add( "ClientConnect", "SendPluginData", function( Client )
		Shine:SendPluginData( Client )

		if Shine:HasAccess( Client, "sh_adminmenu" ) then
			AuthedWithAdminMenu:Add( Client )
			SendClientAdminMenuAccess( Client, true )
		end
	end )

	Shine.Hook.Add( "ClientDisconnect", "VoteMenuAdminMenuAuth", function( Client )
		AuthedWithAdminMenu:Remove( Client )
	end )

	Shine.Hook.Add( "OnUserReload", "VoteMenuAdminMenuAuth", function()
		local ClientsToRemove = {}
		local ClientsToAdd = {}

		for Client in Shine.IterateClients() do
			if AuthedWithAdminMenu:Contains( Client ) then
				if not Shine:HasAccess( Client, "sh_adminmenu" ) then
					ClientsToRemove[ #ClientsToRemove + 1 ] = Client
					SendClientAdminMenuAccess( Client, false )
				end
			elseif Shine:HasAccess( Client, "sh_adminmenu" ) then
				ClientsToAdd[ #ClientsToAdd + 1 ] = Client
				SendClientAdminMenuAccess( Client, true )
			end
		end

		AuthedWithAdminMenu:AddAll( ClientsToAdd )
		AuthedWithAdminMenu:RemoveAll( ClientsToRemove )
	end )
end

local VoteMenuPlugins = {
	voterandom = true,
	mapvote = true,
	votesurrender = true,
	unstuck = true,
	motd = true
}

Shine.Hook.Add( "OnPluginUnload", "SendPluginData", function( Name )
	if not VoteMenuPlugins[ Name ] then return end

	Shine:SendPluginData( nil )
end )

-- Client's requesting plugin data.
Shine.HookNetworkMessage( "Shine_RequestPluginData", function( Client, Message )
	Shine:SendPluginData( Client )
end )

Server.HookNetworkMessage( "Shine_OpenedVoteMenu", function( Client )
	Shine.Hook.Broadcast( "OnVoteMenuOpen", Client )
end )
