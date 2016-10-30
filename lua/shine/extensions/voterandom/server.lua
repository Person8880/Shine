--[[
	Shine vote random plugin.
]]

local Shine = Shine

local Notify = Shared.Message

local Abs = math.abs
local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local GetAllPlayers = Shine.GetAllPlayers
local GetNumPlayers = Shine.GetHumanPlayerCount
local GetOwner = Server.GetOwner
local Max = math.max
local Random = math.random
local SharedTime = Shared.GetTime
local StringFormat = string.format
local TableConcat = table.concat
local tostring = tostring

local Plugin = Plugin
Plugin.Version = "2.0"
Plugin.PrintName = "Shuffle"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteRandom.json"

Plugin.RandomEndTimer = "VoteRandomTimer"

Plugin.EnabledGamemodes = {
	[ "ns2" ] = true,
	[ "mvm" ] = true
}

Plugin.MODE_RANDOM = 1
Plugin.MODE_SCORE = 2
Plugin.MODE_ELO = 3
Plugin.MODE_KDR = 4
Plugin.MODE_HIVE = 5

local ModeStrings = {
	Action = {
		"SHUFFLE_RANDOM",
		"SHUFFLE_SCORE",
		nil,
		"SHUFFLE_KDR",
		"SHUFFLE_HIVE"
	},
	Mode = {
		"RANDOM_BASED",
		"SCORE_BASED",
		nil,
		"KDR_BASED",
		"HIVE_BASED"
	},
	ModeLower = {
		"RANDOM_BASED",
		"SCORE_BASED",
		nil,
		"KDR_BASED",
		"HIVE_BASED"
	}
}
Plugin.ModeStrings = ModeStrings

Plugin.DefaultConfig = {
	MinPlayers = 10, --Minimum number of players on the server to enable voting.
	PercentNeeded = 0.75, --Percentage of the server population needing to vote for it to succeed.

	Duration = 15, --Time to force people onto teams for after a vote. Also time between successful votes.
	BlockAfterTime = 0, --Time after round start to block the vote. 0 to disable blocking.
	RandomOnNextRound = true, --If false, then random teams are forced for a duration instead.
	InstantForce = true, --Forces a shuffle of everyone instantly when the vote succeeds (for time based).
	VoteTimeout = 60, --Time after the last vote before the vote resets.
	NotifyOnVote = true, -- Should all players be told through the chat when a vote is cast?
	ApplyToBots = false, -- Should bots be shuffled, or removed?

	BalanceMode = Plugin.MODE_HIVE, --How should teams be balanced?
	FallbackMode = Plugin.MODE_KDR, --Which method should be used if Elo/Hive fails?
	--[[
		How much of an increase in standard deviation should be allowed if the
		average is being improved but the standard deviation can't be?
	]]
	StandardDeviationTolerance = 40,
	--[[
		How much difference between team averages should be considered good enough?
		The shuffle process will carry on until either it reaches at or below this level,
		or it can't improve the difference anymore.
	]]
	AverageValueTolerance = 0,

	BlockTeams = true, --Should team changing/joining be blocked after an instant force or in a round?
	IgnoreCommanders = true, --Should the plugin ignore commanders when switching?
	IgnoreSpectators = false, --Should the plugin ignore spectators when switching?
	AlwaysEnabled = false, --Should the plugin be always forcing each round?

	ReconnectLogTime = 0, --How long (in seconds) after a shuffle to log reconnecting players for?
	HighlightTeamSwaps = false, -- Should players swapping teams be highlighted on the scoreboard?
	DisplayStandardDeviations = false -- Should the scoreboard show each team's standard deviation of skill?
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Script.Load( Shine.GetPluginFile( "voterandom", "team_balance.lua" ) )

local ModeError = [[Error in voterandom config, FallbackMode is not set as a valid option.
Make sure BalanceMode and FallbackMode are not the same, and that FallbackMode is not 3 (Elo) or 5 (Hive).
Setting FallbackMode to KDR mode (4).]]

local ModeClamp = Shine.IsNS2Combat and 4 or 5

function Plugin:OnFirstThink()
	self:BroadcastModuleEvent( "OnFirstThink" )

	local select = select
	local Hooks = {
		"AddScore", "AddKill", "AddDeaths", "AddAssistKill"
	}
	local StatKeys = {
		"totalScore", "totalKills", "totalDeaths", "totalAssists"
	}
	local StatIndex = {
		1
	}

	for i = 1, #Hooks do
		local Event = Hooks[ i ]
		Shine.Hook.SetupClassHook( "ScoringMixin", Event, Event, "PassivePost" )

		local ExtraKey = StatKeys[ i ]
		local PointsIndex = StatIndex[ i ]
		self[ Event ] = function( self, Player, ... )
			if self:CallModuleEvent( Event, Player, ... ) then return end
			if not GetGamerules():GetGameStarted() then return end

			Player[ ExtraKey ] = ( Player[ ExtraKey ] or 0 ) + ( PointsIndex and select( PointsIndex, ... ) or 1 )
		end
	end
end

function Plugin:Initialise()
	self.Config.BalanceMode = Clamp( Floor( self.Config.BalanceMode or 1 ), 1, ModeClamp )
	self.Config.FallbackMode = Clamp( Floor( self.Config.FallbackMode or 1 ), 1, ModeClamp )
	self.Config.ReconnectLogTime = Max( self.Config.ReconnectLogTime, 0 )

	local BalanceMode = self.Config.BalanceMode
	local FallbackMode = self.Config.FallbackMode

	if BalanceMode == self.MODE_ELO then
		BalanceMode = self.MODE_HIVE
		self.Config.BalanceMode = BalanceMode
		Notify( "NS2Stats Elo mode no longer exists. Switching to Hive skill mode..." )
	end

	if FallbackMode == self.MODE_ELO or FallbackMode == self.MODE_HIVE then
		self.Config.FallbackMode = self.MODE_KDR

		Notify( ModeError )

		self:SaveConfig()
	end

	self:CreateCommands()

	self.NextVote = 0

	local function GetVotesNeeded()
		return self:GetVotesNeeded()
	end

	local function OnVotePassed()
		self:ApplyRandomSettings()
	end

	local function OnTimeout( Vote )
		if Vote.LastVoted and SharedTime() - Vote.LastVoted > self.Config.VoteTimeout then
			Vote:Reset()
		end
	end

	self.Vote = Shine:CreateVote( GetVotesNeeded, OnVotePassed, OnTimeout )
	function self.Vote.OnReset()
		self.dt.CurrentShuffleVotes = 0
		self.dt.RequiredShuffleVotes = 0
	end

	self.ForceRandomEnd = 0 --Time based.
	self.RandomOnNextRound = false --Round based.
	self.ForceRandom = self.Config.AlwaysEnabled

	self.dt.HighlightTeamSwaps = self.Config.HighlightTeamSwaps
	self.dt.DisplayStandardDeviations = self.Config.DisplayStandardDeviations
		and BalanceMode == self.MODE_HIVE

	self:BroadcastModuleEvent( "Initialise" )
	self.Enabled = true

	return true
end

--[[
	Gets all valid targets for sorting.
]]
function Plugin:GetTargetsForSorting( ResetScores )
	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local Players, Count = GetAllPlayers()
	local Targets = {}
	local TeamMembers = {
		{},
		{},
		TeamPreferences = {}
	}

	local AFKEnabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )
	local IsRookieMode = Gamerules.gameInfo and Gamerules.gameInfo:GetRookieMode()

	local function SortPlayer( Player, Client, Commander, Pass )
		local Team = Player:GetTeamNumber()
		if Team == 3 and self.Config.IgnoreSpectators then
			return
		end

		-- Don't move non-rookies on rookie servers.
		if IsRookieMode and not Player:GetIsRookie() then
			return
		end

		local IsImmune = Shine:HasAccess( Client, "sh_randomimmune" ) or Commander

		-- Pass 1, put all immune players into team slots.
		-- This ensures they're picked last if there's a team imbalance at the end of sorting.
		-- It does not stop them from being swapped if it helps overall balance though.
		if Pass == 1 then
			if IsImmune then
				local TeamTable = TeamMembers[ Team ]

				if TeamTable then
					TeamTable[ #TeamTable + 1 ] = Player
				end

				TeamMembers.TeamPreferences[ Player ] = true
			end

			return
		end

		-- Pass 2, put all non-immune players into team slots/target list.
		if IsImmune then return end

		-- If they're on a playing team, bias towards letting them keep it.
		if Team == 1 or Team == 2 then
			local TeamTable = TeamMembers[ Team ]

			TeamTable[ #TeamTable + 1 ] = Player
			TeamMembers.TeamPreferences[ Player ] = true
		else
			Targets[ #Targets + 1 ] = Player
		end
	end

	local function AddPlayer( Player, Pass )
		if not Player then return end

		if Player.ResetScores and ResetScores then
			Player:ResetScores()
		end

		local Client = Player:GetClient()
		if not Client then return end

		-- Bot and we don't want to deal with them, so kick them out.
		if Client:GetIsVirtual() and not self.Config.ApplyToBots then
			if Pass == 1 then
				if Player.Disconnect then
					Player:Disconnect()
				else
					Server.DisconnectClient( Client )
				end
			end

			return
		end

		local Commander = Player:isa( "Commander" ) and self.Config.IgnoreCommanders

		if AFKEnabled then -- Ignore AFK players in sorting.
			if Commander or not AFKKick:IsAFKFor( Client, 60 ) then
				SortPlayer( Player, Client, Commander, Pass )
			elseif Pass == 1 then -- Chuck AFK players into the ready room.
				local Team = Player:GetTeamNumber()

				-- Only move players on playing teams...
				if Team == 1 or Team == 2 then
					Gamerules:JoinTeam( Player, 0, nil, true )
				end
			end

			return
		end

		SortPlayer( Player, Client, Commander, Pass )
	end

	for Pass = 1, 2 do
		for i = 1, Count do
			AddPlayer( Players[ i ], Pass )
		end
	end

	return Targets, TeamMembers
end

--[[
	Shuffles everyone on the server into random teams.
]]
function Plugin:ShuffleTeams( ResetScores, ForceMode )
	local Gamerules = GetGamerules()
	if not Gamerules then return end

	-- Prevent the bot controller interfering with our changes.
	self.OptimisingTeams = true

	local Targets, TeamMembers = self:GetTargetsForSorting( ResetScores )

	self.LastShuffleMode = ForceMode or self.Config.BalanceMode
	self.LastShuffleTime = SharedTime()
	self.ReconnectLogTimeout = SharedTime() + self.Config.ReconnectLogTime
	self.ReconnectingClients = {}

	local Mode = ForceMode or self.Config.BalanceMode
	self.ShufflingModes[ Mode ]( self, Gamerules, Targets, TeamMembers )

	self.OptimisingTeams = false

	-- Remember who was on what team at the point of shuffling, so we can work out
	-- how close to the shuffled teams we are later.
	local TeamLookup = {}
	for i = 1, 2 do
		for j = 1, #TeamMembers[ i ] do
			local Player = TeamMembers[ i ][ j ]
			if Player.GetClient and Player:GetClient() then
				local Client = Player:GetClient()
				local SteamID = Client:GetUserId()
				TeamLookup[ SteamID ] = i
			end
		end
	end
	self.LastShuffleTeamLookup = TeamLookup
end

--[[
	Moves a single player onto a random team.
]]
function Plugin:JoinRandomTeam( Player )
	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local Team1 = Gamerules:GetTeam( kTeam1Index ):GetNumPlayers()
	local Team2 = Gamerules:GetTeam( kTeam2Index ):GetNumPlayers()

	if Team1 < Team2 then
		Gamerules:JoinTeam( Player, 1 )
	elseif Team2 < Team1 then
		Gamerules:JoinTeam( Player, 2 )
	else
		if self.LastShuffleMode == self.MODE_HIVE then
			local Team1Players = Gamerules.team1:GetPlayers()
			local Team2Players = Gamerules.team2:GetPlayers()

			local Team1Skill = self:GetAverageSkill( Team1Players )
			local Team2Skill = self:GetAverageSkill( Team2Players )

			--If team skill is identical, then we should just pick a random team.
			if Team1Skill.Average ~= Team2Skill.Average then
				local BetterTeam = Team1Skill.Average > Team2Skill.Average and 1 or 2

				local PlayerSkill = Player.GetPlayerSkill and Player:GetPlayerSkill() or 0
				local TeamToJoin = BetterTeam == 1 and 2 or 1

				local NewTeam1Average = ( Team1Skill.Total + PlayerSkill ) / ( Team1Skill.Count + 1 )
				local NewTeam2Average = ( Team2Skill.Total + PlayerSkill ) / ( Team2Skill.Count + 1 )

				--If we're going to make the lower team even worse, then put them on the "better" team.
				if BetterTeam == 1 and NewTeam2Average < Team2Skill.Average then
					TeamToJoin = 1
				elseif BetterTeam == 2 and NewTeam1Average < Team1Skill.Average then
					TeamToJoin = 2
				end

				Gamerules:JoinTeam( Player, TeamToJoin )

				return
			end
		end

		if Random() < 0.5 then
			Gamerules:JoinTeam( Player, 1 )
		else
			Gamerules:JoinTeam( Player, 2 )
		end
	end
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
	-- Reset the block time when the round stops.
	if NewState == kGameState.NotStarted then
		self.VoteBlockTime = nil
	end

	if NewState ~= kGameState.Countdown then return end

	self:BroadcastModuleEvent( "GameStarting", Gamerules )

	--Block the vote after the set time.
	if self.Config.BlockAfterTime > 0 then
		self.VoteBlockTime = SharedTime() + self.Config.BlockAfterTime * 60
	end

	if not self.Config.AlwaysEnabled then return end
	if GetNumPlayers() < self.Config.MinPlayers then
		return
	end

	if self.DoneStartShuffle then return end

	self.DoneStartShuffle = true

	local OldValue = self.Config.IgnoreCommanders

	--Force ignoring commanders.
	self.Config.IgnoreCommanders = true

	self:SendTranslatedNotify( nil, "AUTO_SHUFFLE", {
		ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
	} )
	self:ShuffleTeams()

	self.Config.IgnoreCommanders = OldValue
end

function Plugin:EndGame( Gamerules, WinningTeam )
	self.DoneStartShuffle = false
	self.VoteBlockTime = nil

	local Players, Count = GetAllPlayers()
	--Reset the randomised state of all players.
	for i = 1, Count do
		local Player = Players[ i ]

		if Player then
			Player.ShineRandomised = nil
		end
	end

	self:BroadcastModuleEvent( "EndGame", Gamerules, WinningTeam, Players )

	--If we're always enabled, we'll shuffle on round start.
	if self.Config.AlwaysEnabled then
		return
	end

	if self.RandomOnNextRound then
		self.RandomOnNextRound = false

		self:SimpleTimer( 15, function()
			local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )

			if Enabled and MapVote:IsEndVote() then
				self.ForceRandom = true

				return
			end

			self:SendTranslatedNotify( nil, "PREVIOUS_VOTE_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()

			self.ForceRandom = true
		end )

		return
	end

	self.ForceRandom = false
	if not self:TimerExists( self.RandomEndTimer ) then return end

	self:SimpleTimer( 15, function()
		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )

		if not ( Enabled and MapVote:IsEndVote() ) then
			self:SendTranslatedNotify( nil, "PREVIOUS_VOTE_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()
		end

		if self:TimerExists( self.RandomEndTimer ) then
			self.ForceRandom = true
		end
	end )
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end
	if not self.ForceRandom then return end

	local Gamestate = Gamerules:GetGameState()

	--We'll do a mass balance, don't worry about them yet.
	if self.Config.AlwaysEnabled and Gamestate < kGameState.PreGame then return end

	--Don't block them from going back to the ready room at the end of the round.
	if Gamestate == kGameState.Team1Won or Gamestate == kGameState.Team2Won
	or GameState == kGameState.Draw then return end

	local Client = GetOwner( Player )
	if not Client then return false end

	local Immune = Shine:HasAccess( Client, "sh_randomimmune" )
	if Immune then return end

	local Team = Player:GetTeamNumber()
	local OnPlayingTeam = Shine.IsPlayingTeam( Team )

	local NumTeam1 = Gamerules.team1:GetNumPlayers()
	local NumTeam2 = Gamerules.team2:GetNumPlayers()

	local ImbalancedTeams = Abs( NumTeam1 - NumTeam2 ) >= 2

	--Do not allow cheating the system.
	if OnPlayingTeam and self.Config.BlockTeams then
		--Allow players to switch if teams are imbalanced.
		if ImbalancedTeams then
			local MorePlayersTeam = NumTeam1 > NumTeam2 and 1 or 2
			if Team == MorePlayersTeam then
				return
			end
		end
		--Spamming F4 shouldn't spam messages...
		if Shine:CanNotify( Client ) then
			self:SendTranslatedNotify( Player, "TEAM_SWITCH_DENIED", {
				ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
			} )
		end

		return false
	end

	if not Player.ShineRandomised then
		if ( Team == 0 or Team == 3 ) and Shine.IsPlayingTeam( NewTeam ) then --They're going from the ready room/spectate to a team.
			Player.ShineRandomised = true --Prevent an infinite loop!

			self:NotifyTranslated( Player, self.LastShuffleMode == self.MODE_HIVE and "PLACED_ON_HIVE_TEAM"
				or "PLACED_ON_RANDOM_TEAM" )

			self:JoinRandomTeam( Player )

			return false
		end
	else
		--They came from ready room or spectate, i.e, we just randomised them.
		if Team == 0 or Team == 3 then
			Player.ShineRandomised = nil

			return
		end
	end
end

function Plugin:ClientDisconnect( Client )
	self:BroadcastModuleEvent( "ClientDisconnect", Client )
	self.Vote:ClientDisconnect( Client )

	if not self.ReconnectLogTimeout then return end
	if SharedTime() > self.ReconnectLogTimeout then return end

	self.ReconnectingClients[ Client:GetUserId() ] = true
end

function Plugin:ClientConnect( Client )
	if not self.ReconnectingClients or not self.ReconnectLogTimeout then return end

	if SharedTime() > self.ReconnectLogTimeout then
		self.ReconnectingClients = nil

		return
	end

	if not self.ReconnectingClients[ Client:GetUserId() ] then return end

	self:Print( "Client %s reconnected after a shuffle vote.", true,
		Shine.GetClientInfo( Client ) )
end

function Plugin:GetVotesNeeded()
	local PlayerCount = GetNumPlayers()

	return Ceil( PlayerCount * self.Config.PercentNeeded )
end

function Plugin:GetStartFailureMessage()
	return "ERROR_CANNOT_START", { ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ] }
end

function Plugin:CanStartVote()
	local PlayerCount = GetNumPlayers()

	if PlayerCount < self.Config.MinPlayers then
		return false, "ERROR_NOT_ENOUGH_PLAYERS"
	end

	if self.NextVote >= SharedTime() then
		return false, self:GetStartFailureMessage()
	end

	if self.RandomOnNextRound then
		return false, "ERROR_ALREADY_ENABLED", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
	end

	return true
end

--[[
	Adds a player's vote to the counter.
]]
function Plugin:AddVote( Client )
	if self.Config.AlwaysEnabled then
		return false, "ERROR_TEAMS_FORCED", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
	end

	if self.VoteBlockTime and self.VoteBlockTime < SharedTime() then
		return false, "ERROR_ROUND_TOO_FAR"
	end

	if not Client then Client = "Console" end

	do
		local Allow, Error, TranslationKey, Args = Shine.Hook.Call( "OnVoteStart", "random" )
		if Allow == false then
			return false, TranslationKey, Args
		end
	end

	do
		local Success, Err, Args = self:CanStartVote()
		if not Success then
			return false, Err, Args
		end
	end

	if not self.Vote:AddVote( Client ) then
		return false, "ERROR_ALREADY_VOTED", { ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ] }
	end

	return true
end

--[[
	Timeout the vote.
]]
function Plugin:Think()
	self.Vote:Think()
end

--[[
	Applies the configured randomise settings.
	If set to random teams on next round, it queues a force of random teams for the next round.
	If set to a time duration, it enables random teams and queues the disabling of them.
]]
function Plugin:ApplyRandomSettings()
	self.RandomApplied = true
	self:SimpleTimer( 0, function()
		self.RandomApplied = false
	end )

	--Set up teams for the next round.
	if self.Config.RandomOnNextRound then
		local Gamerules = GetGamerules()

		--Game hasn't started, apply the settings now, as the next round is the one that's going to start...
		if not Gamerules:GetGameStarted() then
			self:SendTranslatedNotify( nil, "NEXT_ROUND_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()

			self.ForceRandom = true

			return
		end

		self:SendTranslatedNotify( nil, "TEAMS_FORCED_NEXT_ROUND", {
			ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
		} )

		self.RandomOnNextRound = true

		return
	end

	--Set up teams now and make them last for the given time in the config.
	local Duration = self.Config.Duration * 60

	if Duration > 5 then
		self.ForceRandom = true
		self.NextVote = SharedTime() + Duration

		self:SendTranslatedNotify( nil, "TEAMS_SHUFFLED_FOR_DURATION", {
			ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ],
			Duration = Floor( Duration )
		} )

		self:CreateTimer( self.RandomEndTimer, Duration, 1, function()
			self:SendTranslatedNotify( nil, "TEAM_ENFORCING_TIMELIMIT", {
				ShuffleType = ModeStrings.Mode[ self.LastShuffleMode or self.Config.BalanceMode ]
			} )
			self.ForceRandom = false
		end )
	end

	if self.Config.InstantForce then
		local Gamerules = GetGamerules()

		local Started = Gamerules:GetGameStarted()

		if Started then
			self:SendTranslatedNotify( nil, "SHUFFLE_AND_RESTART", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams( true )
		else
			self:SendTranslatedNotify( nil, "SHUFFLING_TEAMS", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()
		end

		if Started then
			Gamerules:ResetGame()
		end
	end
end

function Plugin:CreateCommands()
	local function VoteRandom( Client )
		if not Client then return end

		local Player = Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "NSPlayer"

		local Success, Err, Args = self:AddVote( Client )

		if Success then
			local VotesNeeded = self.Vote:GetVotesNeeded()

			if not self.RandomApplied then
				if self.Config.NotifyOnVote then
					self:SendTranslatedNotify( nil, "PLAYER_VOTED", {
						ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ],
						VotesNeeded = VotesNeeded,
						PlayerName = PlayerName
					} )
				else
					self:SendTranslatedNotify( Client, "PLAYER_VOTED_PRIVATE", {
						ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ],
						VotesNeeded = VotesNeeded,
					} )
				end

				self.dt.CurrentShuffleVotes = self.Vote:GetVotes()
				self.dt.RequiredShuffleVotes = self:GetVotesNeeded()
			end

			--Somehow it didn't apply random settings??
			if VotesNeeded == 0 and not self.RandomApplied then
				self:ApplyRandomSettings()
			end

			return
		end

		if not Args then
			self:NotifyTranslatedError( Player, Err )
		else
			self:SendTranslatedError( Player, Err, Args )
		end
	end
	local VoteRandomCommand = self:BindCommand( "sh_voterandom",
		{ "random", "voterandom", "randomvote", "shuffle", "voteshuffle", "shufflevote" },
		VoteRandom, true )
	VoteRandomCommand:Help( "Votes to force shuffled teams." )

	local function ForceRandomTeams( Client, Enable )
		if Enable then
			self.Vote:Reset()
			self:ApplyRandomSettings()

			self:SendTranslatedMessage( Client, "ENABLED_TEAMS", {
				ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
			} )
		else
			self:DestroyTimer( self.RandomEndTimer )
			self.Vote:Reset()

			self.RandomOnNextRound = false
			self.ForceRandom = false

			self.Config.AlwaysEnabled = false

			self:SendTranslatedNotify( nil, "DISABLED_TEAMS", {
				ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
			} )
		end
	end
	local ForceRandomCommand = self:BindCommand( "sh_enablerandom",
		{ "enablerandom", "enableshuffle" }, ForceRandomTeams )
	ForceRandomCommand:AddParam{ Type = "boolean", Optional = true,
		Default = function() return not self.ForceRandom end }
	ForceRandomCommand:Help( "Enables (and applies) or disables forcing shuffled teams." )

	local function ViewTeamStats( Client )
		if self.Config.BalanceMode ~= self.MODE_HIVE then
			if not Client then
				Notify( "Hive balancing is not currently enabled." )
				return
			end

			self:NotifyTranslatedCommandError( Client, "ERROR_NOT_HIVE_BASED" )

			return
		end

		local TeamStats = self:GetTeamStats()
		local Message = {}

		Message[ 1 ] = "Team stats:"

		for i = 1, 2 do
			Message[ #Message + 1 ] = "========="
			Message[ #Message + 1 ] = Shine:GetTeamName( i, true )
			Message[ #Message + 1 ] = "========="

			local Stats = TeamStats[ i ]
			local Skills = Stats.Skills
			for j = 1, #Skills do
				Message[ #Message + 1 ] = tostring( Skills[ j ] )
			end

			Message[ #Message + 1 ] = StringFormat( "Average: %.1f. Standard Deviation: %.1f",
				Stats.Average, Stats.StandardDeviation )
		end

		Message[ #Message + 1 ] = StringFormat( "Tolerance values: %.1f SD / %.1f Av",
			self.Config.StandardDeviationTolerance, self.Config.AverageValueTolerance )
		if self.LastShuffleTime then
			Message[ #Message + 1 ] = StringFormat(
				"Last shuffle was %s ago. %i/%i players match their team from the last shuffle.",
				string.TimeToString( SharedTime() - self.LastShuffleTime ),
				TeamStats.NumMatchingTeams or 0,
				TeamStats.TotalPlayers or 0 )
		else
			Message[ #Message + 1 ] = "Teams have not yet been shuffled."
		end

		if not Client then
			Notify( TableConcat( Message, "\n" ) )
		else
			for i = 1, #Message do
				ServerAdminPrint( Client, Message[ i ] )
			end
		end
	end
	local StatsCommand = self:BindCommand( "sh_teamstats", nil, ViewTeamStats, true )
	StatsCommand:Help( "View Hive skill based team statistics." )
end

Script.Load( Shine.GetPluginFile( "voterandom", "local_stats.lua" ) )
