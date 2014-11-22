--[[
	Shine voting radial menu server side.
]]

local function BuildPluginData( self )
	local Plugins = self.Plugins

	return {
		Shuffle = self:IsExtensionEnabled( "voterandom" ),
		RTV = self:IsExtensionEnabled( "mapvote" ) and Plugins.mapvote.Config.EnableRTV or false,
		Surrender = self:IsExtensionEnabled( "votesurrender" ),
		Unstuck = self:IsExtensionEnabled( "unstuck" ),
		MOTD = self:IsExtensionEnabled( "motd" )
	}
end

function Shine:SendPluginData( Player )
	self:ApplyNetworkMessage( Player, "Shine_PluginData", BuildPluginData( self ), true )
end

--Send plugin data on client connect.
Shine.Hook.Add( "ClientConnect", "SendPluginData", function( Client )
	Shine:SendPluginData( Client )
end )

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

--Client's requesting plugin data.
Server.HookNetworkMessage( "Shine_RequestPluginData", function( Client, Message )
	Shine:SendPluginData( Client )
end )

Server.HookNetworkMessage( "Shine_OpenedVoteMenu", function( Client )
	Shine.Hook.Call( "OnVoteMenuOpen", Client )
end )
