--[[
	Shine surrender vote plugin.
]]

local Shine = Shine

local GetOwner = Server.GetOwner
local SharedTime = Shared.GetTime
local StringFormat = string.format

local Ceil = math.ceil
local Floor = math.floor
local Max = math.max
local Random = math.random

local Plugin = Plugin
Plugin.Version = "1.2"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteSurrender.json"

Plugin.DefaultConfig = {
	PercentNeeded = 0.75, --Percentage of the team needing to vote in order to surrender.
	VoteDelay = 10, --Time after round start before surrender vote is available
	MinPlayers = 6, --Min players needed for voting to be enabled.
	VoteTimeout = 120, --How long after no votes before the vote should reset?
	AllowVoteWithMultipleBases = true --Is a team allowed to surrender with multiple bases
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	local function VoteTimeout( Vote )
		local LastVoted = Vote.LastVoted
		if LastVoted and SharedTime() - LastVoted > self.Config.VoteTimeout then
			Vote:Reset()
		end
	end

	self.Votes = {
		Shine:CreateVote( function() return self:GetVotesNeeded( 1 ) end,
			function() self:Surrender( 1 ) end, VoteTimeout ),

		Shine:CreateVote( function() return self:GetVotesNeeded( 2 ) end,
			function() self:Surrender( 2 ) end, VoteTimeout )
	}

	self.NextVote = 0

	self.dt.ConcedeTime = self.Config.VoteDelay

	self:CreateCommands()

	self.Enabled = true

	return true
end

--[[
	Runs when the game state is set.
	If a round has started, we set the next vote time to current time + delay.
]]
function Plugin:SetGameState( Gamerules, State, OldState )
	if State == kGameState.Started then
		self.NextVote = SharedTime() + ( self.Config.VoteDelay * 60 )
	end
end

function Plugin:GetTeamPlayerCount( Team )
	local Gamerules = GetGamerules()

	if Team == 1 then
		return Gamerules.team1:GetNumPlayers()
	else
		return Gamerules.team2:GetNumPlayers()
	end
end

function Plugin:GetVotesNeeded( Team )
	local TeamCount = self:GetTeamPlayerCount( Team )

	return Max( 1, Ceil( TeamCount * self.Config.PercentNeeded ) )
end

--[[
	Make sure we only vote when a round has started and
	the team data pass the config params
]]
function Plugin:CanStartVote( Team )
	local Gamerules = GetGamerules()

	if not Gamerules then return false end

	local State = Gamerules:GetGameState()
	local PlayingTeam = Gamerules:GetTeam( Team )
	local TeamCount = PlayingTeam:GetNumPlayers()

	local AllowWithNumBases = self.Config.AllowVoteWithMultipleBases or
			PlayingTeam:GetNumCapturedTechPoints() == 1

	return State == kGameState.Started and AllowWithNumBases and
			TeamCount >= self.Config.MinPlayers and self.NextVote < SharedTime()
end

function Plugin:AddVote( Client, Team )
	if not Client then return end

	--Would be a fun bug...
	if Team ~= 1 and Team ~= 2 then return false, "spectators can't surrender!" end
	
	if not self:CanStartVote( Team ) then return false, "can't start" end
	local Success, Err = self.Votes[ Team ]:AddVote( Client )

	if not Success then return false, Err end

	return true
end

--[[
	Timeout the vote. 1 minute and no votes should reset it.
]]
function Plugin:Think()
	for i = 1, 2 do
		self.Votes[ i ]:Think()
	end
end

--[[
	Remove a client's vote if they disconnect!
]]
function Plugin:ClientDisconnect( Client )
	for i = 1, 2 do
		self.Votes[ i ]:ClientDisconnect( Client )
	end
end

--[[
	Remove a client's vote if they leave the team!
]]
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if not Player then return end
	local Client = GetOwner( Player )

	if not Client then return end

	local Vote = self.Votes[ OldTeam ]

	if Vote then
		Vote:RemoveVote( Client )
	end
end

--[[
	Makes the given team surrender.
]]
function Plugin:Surrender( Team )
	local Gamerules = GetGamerules()

	if not Gamerules then return end

	Shine.SendNetworkMessage( "TeamConceded", { teamNumber = Team } )

	Gamerules:EndGame( Team == 1 and Gamerules.team2 or Gamerules.team1 )

	self.Surrendered = true

	self:SimpleTimer( 0, function()
		self.Surrendered = false
	end )
end

--[[
	Overrides the concede vote button in the NS2 request menu.
]]
function Plugin:CastVoteByPlayer( Gamerules, ID, Player )
	if not Player then return end
	if ID ~= kTechId.VoteConcedeRound then return end
	
	local Client = Player:GetClient()
	if not Client then return true end

	local Team = Player:GetTeam():GetTeamNumber()
	if not self.Votes[ Team ] then return true end

	local Votes = self.Votes[ Team ]:GetVotes()
	local Success, Err = self:AddVote( Client, Team )

	--We failed to add the vote, but we should still stop it going through NS2's system...
	if not Success then return true end
	--We've surrendered, no need to say another player's voted.
	if self.Surrendered then return true end

	local VotesNeeded = self.Votes[ Team ]:GetVotesNeeded()
	
	self:AnnounceVote( Player, Team, VotesNeeded )

	return true
end

function Plugin:AnnounceVote( Player, Team, VotesNeeded )
	local Players = GetEntitiesForTeam( "Player", Team )

	local NWMessage = {
		voterName = Player:GetName(),
		votesMoreNeeded = VotesNeeded
	}

	for i = 1, #Players do
		local Ply = Players[ i ]

		if Ply then
			--Use NS2's built in concede, it's localised.
			Shine.SendNetworkMessage( Ply, "VoteConcedeCast", NWMessage, true )
		end
	end
end
			
function Plugin:CreateCommands()
	local function VoteSurrender( Client )
		if not Client then return end

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		local Team = Player:GetTeamNumber()

		if not self.Votes[ Team ] then
			Shine:NotifyError( Player, "You cannot start a surrender vote on this team." )

			return
		end
		
		local Success, Err = self:AddVote( Client, Team )

		if Success then
			if self.Surrendered then return end

			local VotesNeeded = self.Votes[ Team ]:GetVotesNeeded()

			return self:AnnounceVote( Player, Team, VotesNeeded )
		end

		if Err == "already voted" then
			Shine:NotifyError( Player, "You have already voted to surrender." )
		else
			Shine:NotifyError( Player, "You cannot start a surrender vote at this time." )
		end
	end
	local VoteSurrenderCommand = self:BindCommand( "sh_votesurrender",
		{ "surrender", "votesurrender", "surrendervote" }, VoteSurrender, true )
	VoteSurrenderCommand:Help( "Votes to surrender the round." )
end
