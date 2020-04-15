--[[
	Vote to draw the current round.
]]

local Plugin = ...

local assert = assert
local Ceil = math.ceil
local SharedTime = Shared.GetTime

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteDraw.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.DefaultConfig = {
	-- How long into a round to wait before allowing a vote to draw the game.
	EnableAfterRoundStartMinutes = 20,

	-- Whether to notify everyone of votes, or just the voting player (vote menu button updates regardless).
	NotifyOnVote = true,

	-- The fraction of players on both playing teams needing to vote for it to pass.
	FractionNeededToPass = 0.9,

	-- How long to wait between votes before the vote is reset.
	VoteTimeoutInSeconds = 60,

	-- Standard vote settings.
	VoteSettings = {
		ConsiderAFKPlayersInVotes = true,
		AFKTimeInSeconds = 60
	}
}

do
	local Validator = Shine.Validator()

	Validator:AddFieldRule( "FractionNeededToPass", Validator.Clamp( 0, 1 ) )
	Validator:AddFieldRule( "EnableAfterRoundStartMinutes", Validator.Min( 0 ) )
	Validator:AddFieldRule( "VoteTimeoutInSeconds", Validator.Min( 0 ) )
	Validator:CheckTypesAgainstDefault( "VoteSettings", Plugin.DefaultConfig.VoteSettings )
	Validator:AddFieldRule( "VoteSettings.AFKTimeInSeconds", Validator.Min( 0 ) )

	Plugin.ConfigValidator = Validator
end

-- Show all votes to draw the game, even the last that triggers it.
Plugin.ShowLastVote = true
Plugin.VoteCommand = {
	ConCommand = "sh_votedraw",
	ChatCommand = "votedraw",
	Help = "Votes to end the current round as a draw."
}

function Plugin:OnVotePassed()
	local Gamerules = GetGamerules()
	assert( Gamerules, "Couldn't find the gamerules!" )

	Gamerules:DrawGame()
end

function Plugin:CanStartVote()
	local Gamerules = GetGamerules()
	if not Gamerules or not Gamerules:GetGameStarted() then
		return false, "ERROR_ROUND_NOT_STARTED"
	end

	local StartTime = Gamerules:GetGameStartTime()
	local TimeTillVoteAllowed = StartTime + self.Config.EnableAfterRoundStartMinutes * 60 - SharedTime()
	if TimeTillVoteAllowed > 0 then
		return false, "ERROR_MUST_WAIT", {
			SecondsToWait = Ceil( TimeTillVoteAllowed )
		}
	end

	return true
end

local function GetNumPlayersOnTeam( Team, AFKTime, AFKKick )
	local Count = 0

	Team:ForEachPlayer( function( Player )
		local Client = Player:GetClient()
		if Client and Client:GetIsVirtual() then return end

		if not Client or not ( AFKTime and AFKKick and AFKKick:IsAFKFor( Client, AFKTime ) ) then
			Count = Count + 1
		end
	end )

	return Count
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam )
	if not Shine.IsPlayingTeam( OldTeam ) or Shine.IsPlayingTeam( NewTeam ) then return end

	-- If a player goes to the ready room or spectate, remove their vote.
	local Client = Player:GetClient()
	if self.Vote:RemoveVote( Client ) and not self.Vote:CheckForSuccess() then
		self:UpdateVoteCounters( self.Vote )
		self:NotifyVoteReset( Client )
	end
end

function Plugin:GetPlayerCountForVote()
	local Gamerules = GetGamerules()
	assert( Gamerules, "Cannot get player count without the gamerules!" )

	local AFKTime = not self.Config.VoteSettings.ConsiderAFKPlayersInVotes and self.Config.VoteSettings.AFKTimeInSeconds
	local Enabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )

	local Count = 0
	for i = 1, 2 do
		Count = Count + GetNumPlayersOnTeam( Gamerules:GetTeam( i ), AFKTime, Enabled and AFKKick )
	end

	return Count
end

function Plugin:CanClientVote( Client )
	if Client:GetIsVirtual() then
		return false, "ERROR_BOT_CANNOT_VOTE"
	end

	local Player = Client:GetControllingPlayer()
	if not Player or not Player.GetTeamNumber or not Shine.IsPlayingTeam( Player:GetTeamNumber() ) then
		return false, "ERROR_CANNOT_VOTE_ON_CURRENT_TEAM"
	end

	return true
end
