--[[
	Shuffle plugin shared code.
]]

local StringFormat = string.format

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = {
	100, 255, 100
}
Plugin.EnabledGamemodes = {
	[ "ns2" ] = true,
	[ "mvm" ] = true
}

do
	local Values = {
		"ALLOW_ALL", "REQUIRE_INVITE", "BLOCK"
	}
	Plugin.FriendGroupJoinType = table.AsEnum( Values, function( Index ) return Index end )
	Plugin.FriendGroupJoinTypeName = table.AsEnum( Values )

	Values = { "ALLOW_ALL_TO_JOIN", "LEADER_ADD_ONLY" }
	Plugin.FriendGroupLeaderType = table.AsEnum( Values, function( Index ) return Index end )
	Plugin.FriendGroupLeaderTypeName = table.AsEnum( Values )
end

Plugin.ShuffleMode = table.AsEnum{
	"RANDOM", "SCORE", "INVALID", "KDR", "HIVE"
}

Plugin.ModeStrings = {
	Action = {
		[ Plugin.ShuffleMode.RANDOM ] = "SHUFFLE_RANDOM",
		[ Plugin.ShuffleMode.SCORE ] = "SHUFFLE_SCORE",
		[ Plugin.ShuffleMode.KDR ] = "SHUFFLE_KDR",
		[ Plugin.ShuffleMode.HIVE ] = "SHUFFLE_HIVE"
	},
	Mode = {
		[ Plugin.ShuffleMode.RANDOM ] = "RANDOM_BASED",
		[ Plugin.ShuffleMode.SCORE ] = "SCORE_BASED",
		[ Plugin.ShuffleMode.KDR ] = "KDR_BASED",
		[ Plugin.ShuffleMode.HIVE ] = "HIVE_BASED"
	}
}

Plugin.VoteMessageKeys = {
	"PLAYER_VOTED",
	"PLAYER_VOTED_ENABLE_AUTO",
	"PLAYER_VOTED_DISABLE_AUTO"
}
Plugin.FriendGroupMessageKeys = {
	"ADDED_TO_FRIEND_GROUP",
	"INVITE_ACCEPTED",
	"INVITE_REJECTED",
	"SELF_INVITE_ACCEPTED",
	"REMOVED_FROM_GROUP"
}

function Plugin:SetupDataTable()
	self:CallModuleEvent( "SetupDataTable" )

	self:AddDTVar( "boolean", "HighlightTeamSwaps", false )
	self:AddDTVar( "boolean", "DisplayStandardDeviations", false )

	self:AddDTVar( "boolean", "IsAutoShuffling", false )
	self:AddDTVar( "boolean", "IsVoteForAutoShuffle", false )

	self:AddDTVar( "boolean", "IsFriendGroupingEnabled", false )

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
		},
		GroupWithPlayer = {
			PlayerName = self:GetNameNetworkField()
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
		[ MessageTypes.PlayerVote ] = self.VoteMessageKeys,
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

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.GroupWithPlayer ] = self.FriendGroupMessageKeys
	} )
	self:AddNetworkMessages( "AddTranslatedNotification", {
		[ MessageTypes.GroupWithPlayer ] = {
			"ERROR_FRIEND_GROUP_FULL", "ERROR_TARGET_FRIEND_GROUP_FULL", "ERROR_TARGET_IN_FRIEND_GROUP",
			"ERROR_TARGET_OPTED_OUT", "ERROR_TARGET_ALREADY_INVITED", "ERROR_MUST_BE_INVITED_TO_GROUP",
			"ERROR_INVITE_ON_COOLDOWN", "ERROR_CANNOT_REMOVE_NOT_LEADER", "SENT_INVITE_TO_FRIEND_GROUP"
		}
	} )

	self:AddNetworkMessage( "TeamPreference", { PreferredTeam = "integer" }, "Server" )
	self:AddNetworkMessage( "TemporaryTeamPreference", { PreferredTeam = "integer", Silent = "boolean" }, "Client" )
	self:AddNetworkMessage( "GroupTeamPreference", { PreferredTeam = "integer", Silent = "boolean" }, "Client" )

	local FriendGroupJoinTypeField = StringFormat( "integer (1 to %d)", #self.FriendGroupJoinType )
	local FriendGroupLeaderTypeField = StringFormat( "integer (1 to %d)", #self.FriendGroupLeaderType )

	self:AddNetworkMessage( "ClientFriendGroupConfig", {
		JoinType = FriendGroupJoinTypeField,
		LeaderType = FriendGroupLeaderTypeField
	}, "Server" )

	self:AddNetworkMessage( "FriendGroupInvite", {
		PlayerName = self:GetNameNetworkField(),
		ExpiryTime = "time"
	}, "Client" )
	self:AddNetworkMessage( "FriendGroupInviteCancelled", {}, "Client" )
	self:AddNetworkMessage( "FriendGroupInviteAnswer", {
		Accepted = "boolean"
	}, "Server" )

	self:AddNetworkMessage( "JoinFriendGroup", { SteamID = "integer" }, "Server" )
	self:AddNetworkMessage( "RemoveFromFriendGroup", { SteamID = "integer" }, "Server" )
	self:AddNetworkMessage( "LeaveFriendGroup", {}, "Server" )

	self:AddNetworkMessage( "LeftFriendGroup", {}, "Client" )
	self:AddNetworkMessage( "FriendGroupUpdated", {
		SteamID = "integer",
		Joined = "boolean"
	}, "Client" )
	self:AddNetworkMessage( "FriendGroupConfig", {
		LeaderType = FriendGroupLeaderTypeField,
		LeaderID = "integer"
	}, "Client" )
end

Shine.LoadPluginModule( "sh_vote.lua", Plugin )

return Plugin
