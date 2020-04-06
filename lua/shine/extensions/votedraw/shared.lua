--[[
	Draw vote shared.
]]

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = {
	224, 255, 210
}
Plugin.UseCustomVoteTiming = true
Plugin.HandlesVoteConfig = true
Plugin.FractionConfigKey = "FractionNeededToPass"

function Plugin:SetupDataTable()
	self:CallModuleEvent( "SetupDataTable" )

	local MessageTypes = {
		PlayerVote  = {
			PlayerName = self:GetNameNetworkField(),
			VotesNeeded = "integer"
		},
		PrivateVote = {
			VotesNeeded = "integer"
		},
		VoteWaitTime = {
			SecondsToWait = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.PlayerVote ] = {
			"PLAYER_VOTED"
		},
		[ MessageTypes.PrivateVote ] = {
			"PLAYER_VOTED_PRIVATE"
		}
	} )
	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.VoteWaitTime ] = {
			"ERROR_MUST_WAIT"
		}
	} )
end

Shine.LoadPluginModule( "sh_vote.lua", Plugin, true )

return Plugin
