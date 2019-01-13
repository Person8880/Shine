--[[
	Shuffle plugin shared code.
]]

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = {
	100, 255, 100
}

function Plugin:SetupDataTable()
	self:CallModuleEvent( "SetupDataTable" )

	self:AddDTVar( "boolean", "HighlightTeamSwaps", false )
	self:AddDTVar( "boolean", "DisplayStandardDeviations", false )

	self:AddDTVar( "boolean", "IsAutoShuffling", false )
	self:AddDTVar( "boolean", "IsVoteForAutoShuffle", false )

	local MessageTypes = {
		ShuffleType = {
			ShuffleType = "string (24)"
		},
		ShuffleDuration = {
			ShuffleType = "string (24)",
			Duration = "integer"
		},
		PlayerVote  = {
			ShuffleType = "string (24)",
			PlayerName = self:GetNameNetworkField(),
			VotesNeeded = "integer"
		},
		PrivateVote = {
			ShuffleType = "string (24)",
			VotesNeeded = "integer"
		},
		VoteWaitTime = {
			ShuffleType = "string (24)",
			SecondsToWait = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ MessageTypes.ShuffleType ] = {
			"ENABLED_TEAMS"
		}
	}, "ShuffleType" )
	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.ShuffleType ] = {
			"AUTO_SHUFFLE", "PREVIOUS_VOTE_SHUFFLE",
			"TEAM_SWITCH_DENIED", "NEXT_ROUND_SHUFFLE",
			"TEAMS_FORCED_NEXT_ROUND", "TEAMS_FORCED_END_OF_ROUND",
			"TEAMS_SHUFFLED_UNTIL_NEXT_ROUND", "TEAMS_SHUFFLED_UNTIL_END_OF_ROUND",
			"SHUFFLE_AND_RESTART", "SHUFFLING_TEAMS",
			"TEAM_ENFORCING_TIMELIMIT", "DISABLED_TEAMS",
			"AUTO_SHUFFLE_DISABLED", "AUTO_SHUFFLE_ENABLED"
		},
		[ MessageTypes.ShuffleDuration ] = {
			"TEAMS_SHUFFLED_FOR_DURATION"
		},
		[ MessageTypes.PlayerVote ] = {
			"PLAYER_VOTED", "PLAYER_VOTED_ENABLE_AUTO",
			"PLAYER_VOTED_DISABLE_AUTO"
		},
		[ MessageTypes.PrivateVote ] = {
			"PLAYER_VOTED_PRIVATE", "PLAYER_VOTED_ENABLE_AUTO_PRIVATE",
			"PLAYER_VOTED_DISABLE_AUTO_PRIVATE"
		}
	}, "ShuffleType" )
	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.ShuffleType ] = {
			"ERROR_CANNOT_START", "ERROR_ALREADY_ENABLED",
			"ERROR_TEAMS_FORCED", "ERROR_ALREADY_VOTED"
		},
		[ MessageTypes.VoteWaitTime ] = {
			"ERROR_MUST_WAIT"
		}
	}, "ShuffleType" )

	self:AddNetworkMessage( "TeamPreference", { PreferredTeam = "integer" }, "Server" )
	self:AddNetworkMessage( "TemporaryTeamPreference", { PreferredTeam = "integer", Silent = "boolean" }, "Client" )
end

Shine.LoadPluginModule( "sh_vote.lua", Plugin )

return Plugin
