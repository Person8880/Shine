--[[
	All talk voting.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = {
	0, 200, 255
}

Shine:RegisterExtension( "votealltalk", Plugin )

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
		}
	}, "VoteType" )
end

Shine.LoadPluginModule( "sh_vote.lua", Plugin, true )
