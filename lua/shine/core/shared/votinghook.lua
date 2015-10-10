--[[
-- Shine vanilla voting hook setup
 ]]
Shine.StartNS2Vote = Shine.GetUpValue( HookStartVote, "StartVote", true )

function HookStartVote( VoteName )
	local function BuildNetworkReceiver( VoteName )
		return function( Client, Data )
			if Call( "NS2StartVote", VoteName, Client, Data ) == false then
				Shine.SendNetworkMessage( Client, "VoteCannotStart",
					{
						reason = kVoteCannotStartReason.DisabledByAdmin
					}, true )

				return
			end

			Shine.StartNS2Vote( VoteName, Client, Data )
		end
	end

	Server.HookNetworkMessage( VoteName, BuildNetworkReceiver( VoteName ) )
end

