--[[
	Shine voting radial menu server side.
]]

function Shine:BuildPluginData()
	local Plugins = self.Plugins

	return {
		Shuffle = Plugins.voterandom and Plugins.voterandom.Enabled or false,
		RTV = Plugins.mapvote and Plugins.mapvote.Enabled and Plugins.mapvote.Config.EnableRTV or false,
		Surrender = Plugins.votesurrender and Plugins.votesurrender.Enabled or false,
		Unstuck = Plugins.unstuck and Plugins.unstuck.Enabled or false,
		MOTD = Plugins.motd and Plugins.motd.Enabled or false
	}
end

function Shine:SendPluginData( Player, Data )
	if Player then
		self.SendNetworkMessage( Player, "Shine_PluginData", Data, true )
	else
		local Players = self.GetAllClients()

		for i = 1, #Players do
			self.SendNetworkMessage( Players[ i ], "Shine_PluginData", Data, true )
		end
	end
end

--Send plugin data on client connect.
Shine.Hook.Add( "ClientConnect", "SendPluginData", function( Client )
	Shine:SendPluginData( Client, Shine:BuildPluginData() )
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
	
	Shine:SendPluginData( nil, Shine:BuildPluginData() )
end )

--Client's requesting plugin data.
Server.HookNetworkMessage( "Shine_RequestPluginData", function( Client, Message )
	Shine:SendPluginData( Client, Shine:BuildPluginData() )
end )

Server.HookNetworkMessage( "Shine_OpenedVoteMenu", function( Client )
	Shine.Hook.Call( "OnVoteMenuOpen", Client )
end )
