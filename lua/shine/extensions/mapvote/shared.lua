--[[
	Shared stuff.
]]

local StringFormat = string.format

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = {
	255, 255, 0
}
Plugin.PrintName = "Map Vote"

Plugin.DurationMessageKeys = {
	"MAP_EXTENDED_TIME",
	"SET_MAP_TIME",
	"MAP_EXTENDED_ROUNDS",
	"SET_MAP_ROUNDS"
}

Plugin.VotingMode = table.AsEnum{
	"SINGLE_CHOICE", "MULTIPLE_CHOICE"
}
Plugin.VotingModeOrdinal = table.AsEnum( Plugin.VotingMode, function( Index ) return Index end )

function Plugin:SetupDataTable()
	self:CallModuleEvent( "SetupDataTable" )

	self:AddDTVar( StringFormat( "integer (1 to %d)", #self.VotingModeOrdinal ), "VotingMode", 1 )
	self:AddDTVar( "integer (1 to 255)", "MaxVoteChoicesPerPlayer", 4 )

	local MapNameField = "string (32)"

	local MessageTypes = {
		Duration = {
			Duration = "integer"
		},
		Empty = {},
		MapName = {
			MapName = MapNameField
		},
		MapVotes = {
			MapName = MapNameField,
			Votes = "integer (0 to 127)",
			TotalVotes = "integer (0 to 127)"
		},
		MapNames = {
			MapNames = "string (255)"
		},
		MaxMapChoices = {
			MaxMapChoices = "integer (1 to 255)"
		},
		Nomination = {
			TargetName = self:GetNameNetworkField(),
			MapName = MapNameField
		},
		RTV = {
			TargetName = self:GetNameNetworkField(),
			VotesNeeded = "integer (0 to 127)"
		},
		PlayerVote = {
			TargetName = self:GetNameNetworkField(),
			Revote = "boolean",
			MapName = MapNameField,
			Votes = "integer (0 to 127)",
			TotalVotes = "integer (0 to 127)"
		},
		PlayerVotePrivate = {
			Revote = "boolean",
			MapName = MapNameField,
			Votes = "integer (0 to 127)",
			TotalVotes = "integer (0 to 127)"
		},
		Veto = {
			TargetName = self:GetNameNetworkField()
		},
		TimeLeftCommand = {
			Rounds = "boolean",
			Duration = "integer"
		},
		TeamSwitchFail = {
			IsEndVote = "boolean"
		},
		VoteWaitTime = {
			SecondsToWait = "integer"
		}
	}

	local VoteOptionsMessage = {
		Options = "string (255)",
		CurrentMap = MapNameField,
		Duration = "integer (0 to 1800)",
		NextMap = "boolean",
		ShowTime = "boolean",
		ForceMenuOpen = "boolean",
		TimeLeft = "integer (0 to 32768)"
	}

	local MapVotesMessage = {
		Map = "string (255)",
		Votes = "integer (0 to 255)"
	}

	self:AddNetworkMessage( "VoteOptions", VoteOptionsMessage, "Client" )
	self:AddNetworkMessage( "EndVote", MessageTypes.Empty, "Client" )
	self:AddNetworkMessage( "VoteProgress", MapVotesMessage, "Client" )
	self:AddNetworkMessage( "ChosenMap", {
		MapName = MapNameField,
		IsSelected = "boolean"
	}, "Client" )
	self:AddNetworkMessage( "MapMod", {
		MapName = MapNameField,
		ModID = "string (12)"
	}, "Client" )
	self:AddNetworkMessage( "MapModPrefix", {
		Prefix = MapNameField
	}, "Client" )

	self:AddNetworkMessage( "RequestVoteOptions", MessageTypes.Empty, "Server" )

	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ MessageTypes.Empty ] = {
			"FORCED_VOTE"
		},
		[ MessageTypes.Duration ] = self.DurationMessageKeys
	} )

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.Duration ] = {
			"TimeLeftNotify", "RoundLeftNotify", "EXTENDING_TIME",
			"MAP_CHANGING"
		},
		[ MessageTypes.MapName ] = {
			"MapCycling", "WINNER_NEXT_MAP", "WINNER_CYCLING",
			"CHOOSING_RANDOM_MAP", "NextMapCommand",
			"MAP_CYCLING", "NOMINATED_MAP_CONDITIONALLY"
		},
		[ MessageTypes.MapVotes ] = {
			"WINNER_VOTES", "PLAYER_REVOKED_VOTE_PRIVATE"
		},
		[ MessageTypes.MapNames ] = {
			"VOTES_TIED"
		},
		[ MessageTypes.Nomination ] = {
			"NOMINATED_MAP"
		},
		[ MessageTypes.RTV ] = {
			"RTV_VOTED"
		},
		[ MessageTypes.PlayerVote ] = {
			"PLAYER_VOTED"
		},
		[ MessageTypes.PlayerVotePrivate ] = {
			"PLAYER_VOTED_PRIVATE"
		},
		[ MessageTypes.Veto ] = {
			"VETO"
		},
		[ MessageTypes.TimeLeftCommand ] = {
			"TimeLeftCommand"
		},
		[ MessageTypes.TeamSwitchFail ] = {
			"TeamSwitchFail"
		}
	} )

	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.MapName ] = {
			"VOTE_FAIL_INVALID_MAP", "VOTE_FAIL_VOTED_MAP",
			"MAP_NOT_ON_LIST", "ALREADY_NOMINATED",
			"RECENTLY_PLAYED", "UNCLEAR_MAP_NAME"
		},
		[ MessageTypes.MaxMapChoices ] = {
			"VOTE_FAIL_CHOICE_LIMIT_REACHED"
		},
		[ MessageTypes.VoteWaitTime ] = {
			"VOTE_FAIL_MUST_WAIT"
		}
	} )
end

Shine.LoadPluginModule( "sh_vote.lua", Plugin )

return Plugin
