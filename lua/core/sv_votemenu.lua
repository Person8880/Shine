--[[
	Shine voting radial menu server side.
]]

Shine = Shine or {}

function Shine:SendVoteOptions( Player, Options, Duration )
	if Player then
		Server.SendNetworkMessage( Player, "Shine_VoteMenu", { Options = Options, Duration = Duration }, true )
	else
		local Players = self.GetAllPlayers()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_VoteMenu", { Options = Options, Duration = Duration }, true )
		end
	end
end
