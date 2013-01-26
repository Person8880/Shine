--[[
	Shine voting radial menu server side.
]]

Shine = Shine or {}

function Shine:SendVoteOptions( Player, Options, Duration, NextMap )
	if Player then
		Server.SendNetworkMessage( Player, "Shine_VoteMenu", { Options = Options, Duration = Duration, NextMap = NextMap and 1 or 0 }, true )
	else
		local Players = self.GetAllPlayers()

		local MessageTable = { Options = Options, Duration = Duration, NextMap = NextMap and 1 or 0 }

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_VoteMenu", MessageTable, true )
		end
	end
end

function Shine:BuildPluginData()
	local Plugins = self.Plugins

	return {
		Random = Plugins.voterandom and Plugins.voterandom.Enabled,
		RTV = Plugins.mapvote and Plugins.mapvote.Enabled,
		Scramble = Plugins.votescramble and Plugins.votescramble.Enabled,
		Surrender = Plugins.votesurrender and Plugins.votesurrender.Enabled,
		Unstuck = Plugins.unstuck and Plugins.unstuck.Enabled,
		MOTD = Plugins.motd and Plugins.motd.Enabled
	}
end

function Shine:SendPluginData( Player, Data )
	if Player then
		Server.SendNetworkMessage( Player, "Shine_PluginData", 
			{ 
				Random = Data.Random and 1 or 0, 
				RTV = Data.RTV and 1 or 0,
				Scramble = Data.Scramble and 1 or 0,
				Surrender = Data.Surrender and 1 or 0,
				Unstuck = Data.Unstuck and 1 or 0,
				MOTD = Data.MOTD and 1 or 0
			}, true )
	else
		local Players = self.GetAllPlayers()

		local MessageTable = { 
			Random = Data.Random and 1 or 0, 
			RTV = Data.RTV and 1 or 0,
			Scramble = Data.Scramble and 1 or 0,
			Surrender = Data.Surrender and 1 or 0,
			Unstuck = Data.Unstuck and 1 or 0,
			MOTD = Data.MOTD and 1 or 0
		}

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_PluginData", MessageTable, true )
		end
	end
end

Shine.Hook.Add( "ClientConnect", "SendPluginData", function( Client )
	Shine:SendPluginData( Client, Shine:BuildPluginData() )
end )
