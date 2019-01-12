--[[
	Gamerules overrides.
]]

local Max = math.max
local Min = math.min
local Round = math.Round
local SharedTime = Shared.GetTime
local TableEmpty = table.Empty

local Plugin = ...

function Plugin:SetGameState( Gamerules, NewState, OldState )
	self.dt.Gamestate = NewState
	self:AttemptToConfigureGamerules( Gamerules )

	if NewState == kGameState.Started then
		local Time = SharedTime()
		for i = 1, 2 do
			local Commander = self:GetCommanderForTeam( i )
			if Commander then
				-- Start the commander time tracking, and ensure their duration
				-- is reset from previous rounds.
				self:MarkCommanderLoginTime( Commander, Time, true )
			end
		end
	elseif self.CommanderLogins then
		-- Forget all commander logins when not in a round.
		TableEmpty( self.CommanderLogins )
	end
end

function Plugin:GetCommanderForTeam( TeamNumber )
	return GetEntitiesForTeam( "Commander", TeamNumber )[ 1 ]
end

local function EnsureVotesNeededLargeEnough( VotesNeeded, TotalPlayerCount )
	return Min( Max( Round( VotesNeeded ), 2 ), Max( 1, TotalPlayerCount ) )
end

local function GetEjectVotesNeededFromVoteInterval( VoteInterval, TotalPlayerCount )
	local Fraction = VoteInterval.FractionOfTeamToPass
	return EnsureVotesNeededLargeEnough( Fraction * TotalPlayerCount, TotalPlayerCount )
end

function Plugin:MarkCommanderLoginTime( Commander, Time, ResetDuration )
	if not self.CommanderLogins then return end

	local Client = Commander:GetClient()
	if not Client then return end

	if not Time then
		-- Remove any entry if removing login time.
		self.CommanderLogins[ Client ] = nil
		return
	end

	-- Remember when the commander logged in via their client.
	local Login = self.CommanderLogins[ Client ]
	if not Login then
		Login = {}
		self.CommanderLogins[ Client ] = Login
	end

	Login.LoginTime = Time
	if ResetDuration then
		Login.Duration = 0
	end

	if Time then
		self.Logger:Debug( "%s logged in at %s", Shine.GetClientInfo( Client ), Time )
	end
end

function Plugin:MarkCommanderExitTime( Commander, Time )
	if not self.CommanderLogins then return end

	local Client = Commander:GetClient()
	local Login = self.CommanderLogins[ Client ]
	if not Client or not Login or not Login.LoginTime then return end

	-- When a commander logs out, store the duration they were in the chair so the eject vote
	-- can be based on their total time commanding.
	local ExistingDuration = Login.Duration or 0
	Login.Duration = ExistingDuration + ( Time - Login.LoginTime )
	Login.LoginTime = nil

	self.Logger:Debug( "%s logged out with %s seconds as a commander.",
		Shine.GetClientInfo( Client ), Login.Duration )
end

function Plugin:GetCommanderDuration( Commander )
	local Client = Commander:GetClient()
	local Login = self.CommanderLogins[ Client ]
	if not Client or not Login or not Login.LoginTime then return nil end

	return SharedTime() - Login.LoginTime + ( Login.Duration or 0 )
end

local function LogCommander( Logger, Message, Commander, ... )
	Logger:Debug( Message, Shine.GetClientInfo( Commander:GetClient() ), ... )
end

function Plugin:GetEjectVotesNeeded( VoteManager, TeamNumber )
	local Commander = self:GetCommanderForTeam( TeamNumber )
	local VoteIntervals = self.Config.EjectVotesNeeded
	local TotalPlayerCount = VoteManager.numPlayers

	if not Commander then
		-- Use the first entry if no commander is present.
		local VotesNeeded = GetEjectVotesNeededFromVoteInterval( VoteIntervals[ 1 ], TotalPlayerCount )
		self.Logger:Debug( "No commander present, votes needed: %s", VotesNeeded )
		return VotesNeeded
	end

	-- Time in chair is the time since last login plus any previous time in the chair.
	local TimeInChair = self:GetCommanderDuration( Commander )
	if not TimeInChair then
		-- Round has not yet started, use the lowest value.
		local VotesNeeded = GetEjectVotesNeededFromVoteInterval( VoteIntervals[ 1 ], TotalPlayerCount )

		self.Logger:IfDebugEnabled( LogCommander, "No time in chair recorded for %s, votes needed: %s",
			Commander, VotesNeeded )

		return VotesNeeded
	end

	-- Assume intervals are sorted already (validator ensures they are).
	for i = 1, #VoteIntervals do
		local VoteInterval = VoteIntervals[ i ]
		if not VoteInterval.MaxSecondsAsCommander or TimeInChair <= VoteInterval.MaxSecondsAsCommander then
			local VotesNeeded = GetEjectVotesNeededFromVoteInterval( VoteInterval, TotalPlayerCount )

			self.Logger:IfDebugEnabled( LogCommander,
				"%s has been in the chair for %s seconds, votes needed: %s",
				Commander, TimeInChair, VotesNeeded )

			return VotesNeeded
		end
	end

	-- Shouldn't ever reach this point.
	local VotesNeeded = GetEjectVotesNeededFromVoteInterval( VoteIntervals[ #VoteIntervals ], TotalPlayerCount )

	self.Logger:IfDebugEnabled( LogCommander,
		"%s has been in the chair for %s seconds, votes needed (no matching entry): %s",
		Commander, TimeInChair, VotesNeeded )

	return VotesNeeded
end

function Plugin:OnCommanderLogin( Chair, Commander, Forced )
	local Gamerules = GetGamerules()
	if not Gamerules or not Gamerules:GetGameStarted() then
		-- Do not track time outside of a round.
		self:MarkCommanderLoginTime( Commander, nil, true )
		return
	end

	self:MarkCommanderLoginTime( Commander, SharedTime() )
end

function Plugin:CommLogout( Chair )
	local Commander = Chair:GetCommander()
	if not Commander then return end

	self:MarkCommanderExitTime( Commander, SharedTime() )
end

function Plugin:AttemptToConfigureGamerules( Gamerules )
	if not Gamerules or self.ConfiguredGamerules then return end
	if not Gamerules.team1 or not Gamerules.team2 then return end
	if not Gamerules.team1.ejectCommVoteManager or not Gamerules.team2.ejectCommVoteManager then return end

	self.ConfiguredGamerules = true

	Gamerules.kStartGameVoteDelay = self.Config.CommanderBotVoteDelayInSeconds

	if #self.Config.EjectVotesNeeded == 1 then
		-- If there's just one interval, set the percentage on the vote and leave the
		-- team object alone.
		local VotesNeeded = self.Config.EjectVotesNeeded[ 1 ].FractionOfTeamToPass
		Gamerules.team1.ejectCommVoteManager:SetTeamPercentNeeded( VotesNeeded )
		Gamerules.team2.ejectCommVoteManager:SetTeamPercentNeeded( VotesNeeded )
		self.HasOverriddenTeamVotes = false
		return
	end

	-- Remember when commanders login.
	self.CommanderLogins = {}
	self.HasOverriddenTeamVotes = true

	-- Otherwise, replace the GetNumVotesNeeded method to compute based on interval,
	-- and alter the way votes are checked to avoid running it every tick.
	local function ReplaceGetNumVotesNeeded( VoteManager, TeamNumber )
		VoteManager.GetNumVotesNeeded = function( VoteManager )
			return self:GetEjectVotesNeeded( VoteManager, TeamNumber )
		end
	end

	ReplaceGetNumVotesNeeded( Gamerules.team1.ejectCommVoteManager, 1 )
	ReplaceGetNumVotesNeeded( Gamerules.team2.ejectCommVoteManager, 2 )

	local function FixVoteChecking( Team )
		function Team:UpdateVotes()
			-- Only poll resetting here, not vote passing.
			-- This avoids GetNumVotesNeeded() being called every tick.
			if self.ejectCommVoteManager:GetVoteElapsed( SharedTime() ) then
				self.ejectCommVoteManager:Reset()
			end
			if self.concedeVoteManager:GetVoteElapsed( SharedTime() ) then
				self.concedeVoteManager:Reset()
			end
		end
	end

	FixVoteChecking( Gamerules.team1 )
	FixVoteChecking( Gamerules.team2 )
end

local function UpdateVotePlayerCounts( PlayingTeam, Vote )
	local NumPlayers, _, NumBots = PlayingTeam:GetNumPlayers()
	Vote:SetNumPlayers( NumPlayers - NumBots )
end

function Plugin:EvaluateEjectVote( PlayingTeam )
	local EjectVote = PlayingTeam.ejectCommVoteManager
	if not EjectVote then return end

	UpdateVotePlayerCounts( PlayingTeam, EjectVote )

	if EjectVote:GetVotePassed() then
		local TargetCommander = GetPlayerFromUserId( EjectVote:GetTarget() )
		EjectVote:Reset()

		if TargetCommander and TargetCommander.Eject then
			TargetCommander:Eject()
		end
	end
end

function Plugin:OnVoteToEjectCommander( PlayingTeam, Player, Commander )
	if not self.HasOverriddenTeamVotes then return end

	self:EvaluateEjectVote( PlayingTeam )
end

function Plugin:EvaluateConcedeVote( PlayingTeam )
	local ConcedeVote = PlayingTeam.concedeVoteManager
	if not ConcedeVote then return end

	UpdateVotePlayerCounts( PlayingTeam, ConcedeVote )

	if ConcedeVote:GetVotePassed() then
		ConcedeVote:Reset()
		PlayingTeam.conceded = true
		Shine.SendNetworkMessage( "TeamConceded", { teamNumber = PlayingTeam:GetTeamNumber() } )
	end
end

function Plugin:OnVoteToConcede( PlayingTeam, Player )
	if not self.HasOverriddenTeamVotes then return end

	self:EvaluateConcedeVote( PlayingTeam )
end

function Plugin:EvaluateVotesForTeam( PlayingTeam )
	if not PlayingTeam then return end

	self:EvaluateEjectVote( PlayingTeam )
	self:EvaluateConcedeVote( PlayingTeam )
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	if not self.HasOverriddenTeamVotes then return end

	if OldTeam == 1 or OldTeam == 2 then
		local Team = Gamerules:GetTeam( OldTeam )
		-- Player has left team, check the concede/eject totals again.
		self:EvaluateVotesForTeam( Team )
	end

	local Client = Player:GetClient()
	if not Client then return end

	-- Forget any commander login time for the player if they swap teams.
	self.CommanderLogins[ Client ] = nil
end

function Plugin:UpdateVotesOnDisconnect()
	if not self.HasOverriddenTeamVotes then return end

	local Gamerules = GetGamerules()
	if not Gamerules then return end

	-- Player has left game entirely, check both team's votes.
	for i = 1, 2 do
		local Team = Gamerules:GetTeam( i )
		self:EvaluateVotesForTeam( Team )
	end
end
