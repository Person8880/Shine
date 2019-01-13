--[[
	All talk voting.
]]

local Plugin = Shine.Plugin( ... )
Plugin.NotifyPrefixColour = {
	0, 200, 255
}

function Plugin:SetupDataTable()
	self:CallModuleEvent( "SetupDataTable" )
	self:AddDTVar( "boolean", "IsEnabled", false )

	local MessageTypes = {
		PlayerVote  = {
			VoteType = "string (8)",
			PlayerName = self:GetNameNetworkField(),
			VotesNeeded = "integer"
		},
		PrivateVote = {
			VoteType = "string (8)",
			VotesNeeded = "integer"
		},
		VoteType = {
			VoteType = "string (8)"
		},
		VoteWaitTime = {
			VoteType = "string (8)",
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
	}, "VoteType" )
	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.VoteType ] = {
			"ERROR_ALREADY_VOTED"
		},
		[ MessageTypes.VoteWaitTime ] = {
			"ERROR_MUST_WAIT"
		}
	}, "VoteType" )
end

Shine.LoadPluginModule( "sh_vote.lua", Plugin, true )

return Plugin
