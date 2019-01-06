--[[
	Shine vote random plugin.
]]

local Shine = Shine

local Notify = Shared.Message

local Abs = math.abs
local Ceil = math.ceil
local Clamp = math.Clamp
local DebugGetInfo = debug.getinfo
local Floor = math.floor
local GetAllPlayers = Shine.GetAllPlayers
local GetNumPlayers = Shine.GetHumanPlayerCount
local GetOwner = Server.GetOwner
local IsType = Shine.IsType
local Max = math.max
local Random = math.random
local SharedTime = Shared.GetTime
local StandardDeviation = math.StandardDeviation
local StringFormat = string.format
local TableConcat = table.concat
local tostring = tostring

local Plugin = Plugin
Plugin.Version = "2.4"
Plugin.PrintName = "Shuffle"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteRandom.json"

Plugin.RandomEndTimer = "VoteRandomTimer"

Plugin.EnabledGamemodes = {
	[ "ns2" ] = true,
	[ "mvm" ] = true
}

Plugin.ShufflePolicy = table.AsEnum{
	"INSTANT", "NEXT_ROUND", "END_OF_PERIOD"
}
Plugin.EnforcementDurationType = table.AsEnum{
	"NONE", "TIME", "PERIOD"
}
Plugin.EnforcementPolicyType = table.AsEnum{
	"BLOCK_TEAMS", "ASSIGN_PLAYERS"
}
Plugin.ShuffleMode = table.AsEnum{
	"RANDOM", "SCORE", "INVALID", "KDR", "HIVE"
}
Plugin.TeamPreferenceWeighting = table.AsEnum{
	"NONE", "LOW", "MEDIUM", "HIGH"
}

Plugin.TeamPreferenceWeightingValues = {
	[ Plugin.TeamPreferenceWeighting.NONE ] = 0,
	-- These are derived from simulated optimisation results.
	[ Plugin.TeamPreferenceWeighting.LOW ] = 2,
	[ Plugin.TeamPreferenceWeighting.MEDIUM ] = 3,
	[ Plugin.TeamPreferenceWeighting.HIGH ] = 5
}

Plugin.MODE_RANDOM = Plugin.ShuffleMode.RANDOM
Plugin.MODE_SCORE = Plugin.ShuffleMode.SCORE
Plugin.MODE_ELO = Plugin.ShuffleMode.INVALID
Plugin.MODE_KDR = Plugin.ShuffleMode.KDR
Plugin.MODE_HIVE = Plugin.ShuffleMode.HIVE

local ModeStrings = {
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
	},
	ModeLower = {
		[ Plugin.ShuffleMode.RANDOM ] = "RANDOM_BASED",
		[ Plugin.ShuffleMode.SCORE ] = "SCORE_BASED",
		[ Plugin.ShuffleMode.KDR ] = "KDR_BASED",
		[ Plugin.ShuffleMode.HIVE ] = "HIVE_BASED"
	}
}
Plugin.ModeStrings = ModeStrings

Plugin.DefaultConfig = {
	MinPlayers = 10, -- Minimum number of players on the server to enable voting.
	PercentNeeded = 0.75, -- Percentage of the server population needing to vote for it to succeed.

	VoteCooldownInMinutes = 15, -- Cooldown time before another vote can be made.
	BlockAfterTime = 2, -- Time in minutes after round start to block the vote. 0 to disable blocking.
	VoteTimeout = 60, -- Time after the last vote before the vote resets.
	NotifyOnVote = true, --  Should all players be told through the chat when a vote is cast?
	ApplyToBots = false, --  Should bots be shuffled, or removed?

	BalanceMode = Plugin.ShuffleMode.HIVE, -- How should teams be balanced?
	FallbackMode = Plugin.ShuffleMode.KDR, -- Which method should be used if Elo/Hive fails?

	-- Deprecated parameter controlling how much the standard deviation can increase per swap
	-- in a hard-rule based shuffle.
	StandardDeviationTolerance = 40,
	-- How much difference between team averages should be considered good enough?
	-- The shuffle process will carry on until either it reaches at or below this level,
	-- or it can't improve the difference anymore.
	-- This can terminate the shuffle before it has managed to optimise teams appropriately
	-- and is not recommended.
	AverageValueTolerance = 0,

	IgnoreCommanders = true, -- Should the plugin ignore commanders when switching?
	IgnoreSpectators = false, -- Should the plugin ignore spectators in player slots when switching?
	AlwaysEnabled = false, -- Should the plugin be always forcing each round?

	ReconnectLogTime = 0, -- How long (in seconds) after a shuffle to log reconnecting players for?
	HighlightTeamSwaps = false, -- Should players swapping teams be highlighted on the scoreboard?
	DisplayStandardDeviations = false, -- Should the scoreboard show each team's standard deviation of skill?

	VoteConstraints = {
		-- When the number of players on playing teams is greater-equal this fraction
		-- of the total players on the server, apply constraints.
		MinPlayerFractionToConstrain = 0.9,
		-- The minimum difference in average skill required to permit shuffling.
		-- A value of 0 will permit all votes.
		MinAverageDiffToAllowShuffle = 75,
		-- The minimum difference in standard deviation of skill required to permit shuffling.
		-- Must be greater than 0 to enable checking.
		MinStandardDeviationDiffToAllowShuffle = 0
	},

	--	ShufflePolicy may be one of INSTANT, NEXT_ROUND, END_OF_PERIOD
	--	- INSTANT immediately shuffles the teams
	--	- NEXT_ROUND queues a shuffle for the start of the next round
	--	- END_OF_PERIOD queues a shuffle for the end of the current period, so for PreGame is the same as NEXT_ROUND,
	--	  but for InGame it will shuffle as soon as the players are back in the ready room.

	--	EnforcementDurationType may be one of NONE, TIME, PERIOD
	--	- NONE does not prevent team swaps.
	--	- TIME prevents team swaps and auto-assigns players for the given duration.
	--	- PERIOD prevents team swaps and auto-assigns players for the entire period, at the point of shuffle.
	--	  For example, a shuffle set for next round with period enforcement means teams are blocked for that round.

	--	EnforcementPolicy may be any of BLOCK_TEAMS, ASSIGN_PLAYERS
	--	- BLOCK_TEAMS prevents players from swapping teams, except if there is an imbalance.
	--	- ASSIGN_PLAYERS forces players on the team that benefits from them most when they join a team from the ready room.
	VotePassActions = {
		-- What to do when a vote passes during the pregame.
		PreGame = {
			ShufflePolicy = Plugin.ShufflePolicy.INSTANT,
			EnforcementDurationType = Plugin.EnforcementDurationType.TIME,
			EnforcementPolicy = { Plugin.EnforcementPolicyType.BLOCK_TEAMS, Plugin.EnforcementPolicyType.ASSIGN_PLAYERS },
			DurationInMinutes = 15
		},
		-- What to do when a vote passes during an active game.
		InGame = {
			ShufflePolicy = Plugin.ShufflePolicy.INSTANT,
			EnforcementDurationType = Plugin.EnforcementDurationType.TIME,
			EnforcementPolicy = { Plugin.EnforcementPolicyType.BLOCK_TEAMS, Plugin.EnforcementPolicyType.ASSIGN_PLAYERS },
			DurationInMinutes = 15
		}
	}
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "2.2",
		Apply = function( Config )
			Config.BalanceMode = Plugin.ShuffleMode[ Config.BalanceMode ]
			Config.FallbackMode = Plugin.ShuffleMode[ Config.FallbackMode ]

			local WasInstant = Config.InstantForce
			local EnforcementPolicy = { Plugin.EnforcementPolicyType.ASSIGN_PLAYERS }
			if Config.BlockTeams then
				EnforcementPolicy[ #EnforcementPolicy + 1 ] = Plugin.EnforcementPolicyType.BLOCK_TEAMS
			end
			Config.VotePassActions = {
				PreGame = {
					ShufflePolicy = Plugin.ShufflePolicy.INSTANT,
					EnforcementDurationType = Plugin.EnforcementDurationType.TIME,
					EnforcementPolicy = EnforcementPolicy,
					DurationInMinutes = Config.Duration
				},
				InGame = {
					ShufflePolicy = WasInstant and Plugin.ShufflePolicy.INSTANT or Plugin.ShufflePolicy.END_OF_PERIOD,
					EnforcementDurationType = Plugin.EnforcementDurationType.TIME,
					EnforcementPolicy = EnforcementPolicy,
					DurationInMinutes = Config.Duration
				}
			}
			Config.VoteCooldownInMinutes = Config.Duration

			Config.InstantForce = nil
			Config.Duration = nil
			Config.RandomOnNextRound = nil
			Config.BlockTeams = nil
		end
	},
	{
		VersionTo = "2.4",
		Apply = function( Config )
			if IsType( Config.TeamPreferences, "table" ) then
				Config.TeamPreferences.CostWeighting = Plugin.TeamPreferenceWeighting.NONE
			end
		end
	}
}

do
	local Validator = Shine.Validator()

	Validator:AddFieldRule( "VoteConstraints.MinPlayerFractionToConstrain",
		Validator.IsType( "number", Plugin.DefaultConfig.VoteConstraints.MinPlayerFractionToConstrain ) )
	Validator:AddFieldRules( {
		"VoteConstraints.MinAverageDiffToAllowShuffle",
		"VoteConstraints.MinStandardDeviationDiffToAllowShuffle"
	}, Validator.IsType( "number", 0 ) )

	Validator:AddFieldRule( "VotePassActions.PreGame", Validator.IsType( "table",
		Plugin.DefaultConfig.VotePassActions.PreGame ) )
	Validator:AddFieldRule( "VotePassActions.InGame", Validator.IsType( "table",
		Plugin.DefaultConfig.VotePassActions.InGame ) )
	Validator:AddFieldRules( {
		"VotePassActions.PreGame.ShufflePolicy",
		"VotePassActions.InGame.ShufflePolicy"
	}, Validator.InEnum( Plugin.ShufflePolicy, Plugin.ShufflePolicy.INSTANT ) )
	Validator:AddFieldRules( {
		"VotePassActions.PreGame.EnforcementDurationType",
		"VotePassActions.InGame.EnforcementDurationType"
	}, Validator.InEnum( Plugin.EnforcementDurationType, Plugin.EnforcementDurationType.DURATION ) )
	Validator:AddFieldRules( {
		"VotePassActions.PreGame.EnforcementPolicy",
		"VotePassActions.InGame.EnforcementPolicy"
	}, Validator.Each( Validator.InEnum( Plugin.EnforcementPolicyType ) ) )
	Validator:AddFieldRules( {
		"VotePassActions.PreGame.DurationInMinutes",
		"VotePassActions.InGame.DurationInMinutes"
	}, Validator.IsType( "number", 15 ) )

	Validator:AddFieldRule( "BalanceMode", Validator.InEnum( Plugin.ShuffleMode, Plugin.ShuffleMode.HIVE ) )
	Validator:AddFieldRule( "FallbackMode", Validator.InEnum( Plugin.ShuffleMode, Plugin.ShuffleMode.KDR ) )

	Plugin.ConfigValidator = Validator
end

local EnforcementPolicy = Shine.TypeDef()
function EnforcementPolicy:Init( Policies )
	self.Policies = table.AsSet( Policies )
	return self
end

function EnforcementPolicy:IsActive()
	return false
end

function EnforcementPolicy:OnStageChange( Stage )

end

function EnforcementPolicy:Announce( Plugin )

end

function EnforcementPolicy:JoinTeam( Plugin, Gamerules, Player, NewTeam, Force )
	local Client = GetOwner( Player )
	if not Client then return false end

	local Immune = Shine:HasAccess( Client, "sh_randomimmune" )
	if Immune then return end

	local Team = Player:GetTeamNumber()
	local OnPlayingTeam = Shine.IsPlayingTeam( Team )

	local NumTeam1 = Gamerules.team1:GetNumPlayers()
	local NumTeam2 = Gamerules.team2:GetNumPlayers()

	local ImbalancedTeams = Abs( NumTeam1 - NumTeam2 ) >= 2

	-- Do not allow cheating the system.
	if OnPlayingTeam and self.Policies[ Plugin.EnforcementPolicyType.BLOCK_TEAMS ] then
		-- Allow players to switch if teams are imbalanced.
		if ImbalancedTeams then
			local MorePlayersTeam = NumTeam1 > NumTeam2 and 1 or 2
			if Team == MorePlayersTeam then
				return
			end
		end
		-- Spamming F4 shouldn't spam messages...
		if Shine:CanNotify( Client ) then
			Plugin:SendTranslatedNotify( Player, "TEAM_SWITCH_DENIED", {
				ShuffleType = ModeStrings.Mode[ Plugin.Config.BalanceMode ]
			} )
		end

		return false
	end

	if not self.Policies[ Plugin.EnforcementPolicyType.ASSIGN_PLAYERS ] or ( NumTeam1 == 0 and NumTeam2 == 0 ) then
		-- Skip if not auto-assigning or if both playing teams are empty.
		return
	end

	if not Player.ShineRandomised then
		-- They're going from the ready room/spectate to a team.
		if ( Team == 0 or Team == 3 ) and Shine.IsPlayingTeam( NewTeam ) then
			Player.ShineRandomised = true -- Prevent an infinite loop!

			local TeamJoined = Plugin:JoinRandomTeam( Gamerules, Player )
			if TeamJoined ~= NewTeam then
				-- Notify the player why they're not on their chosen team.
				local Message = Plugin.LastShuffleMode == Plugin.ShuffleMode.HIVE and "PLACED_ON_HIVE_TEAM"
					or "PLACED_ON_RANDOM_TEAM"
				Plugin:NotifyTranslated( Client, Message )
			end

			return false
		end
	else
		-- They came from ready room or spectate, i.e, we just randomised them.
		if Team == 0 or Team == 3 then
			Player.ShineRandomised = nil
			return
		end
	end
end

local DurationBasedEnforcement = Shine.TypeDef( EnforcementPolicy )
function DurationBasedEnforcement:Init( Duration, Policies )
	self.EndTime = SharedTime() + Duration
	self.Duration = Duration
	return EnforcementPolicy.Init( self, Policies )
end

function DurationBasedEnforcement:IsActive()
	return SharedTime() < self.EndTime
end

function DurationBasedEnforcement:Announce( Plugin )
	Plugin:SendTranslatedNotify( nil, "TEAMS_SHUFFLED_FOR_DURATION", {
		ShuffleType = ModeStrings.Mode[ Plugin.Config.BalanceMode ],
		Duration = Floor( self.Duration )
	} )

	Plugin:CreateTimer( Plugin.RandomEndTimer, self.Duration, 1, function()
		Plugin:SendTranslatedNotify( nil, "TEAM_ENFORCING_TIMELIMIT", {
			ShuffleType = ModeStrings.Mode[ Plugin.LastShuffleMode or Plugin.Config.BalanceMode ]
		} )
	end )
end

local PeriodBasedEnforcement = Shine.TypeDef( EnforcementPolicy )
function PeriodBasedEnforcement:Init( InitialStage, Policies )
	self.InitialStage = InitialStage
	self.Active = true
	return EnforcementPolicy.Init( self, Policies )
end

function PeriodBasedEnforcement:IsActive( Plugin )
	return self.Active
end

function PeriodBasedEnforcement:OnStageChange( Stage )
	if Stage ~= self.InitialStage then
		self.Active = false
	end
end

function PeriodBasedEnforcement:Announce( Plugin )
	local Key = self.InitialStage == Plugin.Stage.PreGame and "TEAMS_SHUFFLED_UNTIL_NEXT_ROUND"
		or "TEAMS_SHUFFLED_UNTIL_END_OF_ROUND"
	Plugin:SendTranslatedNotify( nil, Key, {
		ShuffleType = ModeStrings.Mode[ Plugin.Config.BalanceMode ]
	} )
end

local NoOpEnforcement = Shine.TypeDef( EnforcementPolicy )
function NoOpEnforcement:Init()
	return self
end
function NoOpEnforcement:JoinTeam() end

Shine.LoadPluginFile( "voterandom", "team_balance.lua" )

local ModeError = [[Error in voterandom config, FallbackMode is not set as a valid option.
Make sure BalanceMode and FallbackMode are not the same, and that FallbackMode is not "HIVE".
Setting FallbackMode to "KDR" mode.]]

function Plugin:OnFirstThink()
	self:BroadcastModuleEvent( "OnFirstThink" )

	do
		-- Watch when players try to join a team, and use it as their team preference.
		local Commands = {
			{ Event = "Console_j1", Team = 1 },
			{ Event = "Console_jointeamone", Team = 1 },
			{ Event = "Console_j2", Team = 2 },
			{ Event = "Console_jointeamtwo", Team = 2 },
			{ Event = "Console_rr" },
			{ Event = "Console_readyroom" }
		}
		for i = 1, #Commands do
			local Entry = Commands[ i ]
			local Team = Entry.Team
			Event.Hook( Entry.Event, function( Client )
				local Gamerules = GetGamerules()
				if not Gamerules or Gamerules:GetGameStarted() then return end

				if self.Logger:IsDebugEnabled() then
					self.Logger:Debug( "%s has chosen team %s (has persistent preference: %s)",
						Shine.GetClientInfo( Client ), Team, self.TeamPreferences[ Client ] or "none" )
				end

				self.LastAttemptedTeamJoins[ Client ] = Team
				self:SendNetworkMessage( Client, "TemporaryTeamPreference", {
					PreferredTeam = Team or 0,
					-- Don't display a message if voting is disabled (e.g. end of map vote).
					Silent = not self:IsVoteAllowed()
				}, true )
			end )
		end
	end

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
	self.Config.ReconnectLogTime = Max( self.Config.ReconnectLogTime, 0 )

	local BalanceMode = self.Config.BalanceMode
	local FallbackMode = self.Config.FallbackMode

	if BalanceMode == self.ShuffleMode.INVALID then
		BalanceMode = self.ShuffleMode.HIVE
		self.Config.BalanceMode = BalanceMode
		Notify( "NS2Stats Elo mode no longer exists. Switching to Hive skill mode..." )
	end

	if FallbackMode == self.ShuffleMode.INVALID or FallbackMode == self.ShuffleMode.HIVE then
		self.Config.FallbackMode = self.ShuffleMode.KDR

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

	self.Vote = Shine:CreateVote( GetVotesNeeded, self:WrapCallback( OnVotePassed ) )
	self:SetupVoteTimeout( self.Vote, self.Config.VoteTimeout )
	function self.Vote.OnReset()
		self:ResetVoteCounters()
	end

	self.ShuffleOnNextRound = false
	self.ShuffleAtEndOfRound = false
	self.HasShuffledThisRound = false
	self.SuppressAutoShuffle = false

	self.dt.HighlightTeamSwaps = self.Config.HighlightTeamSwaps
	self.dt.DisplayStandardDeviations = self.Config.DisplayStandardDeviations
		and BalanceMode == self.ShuffleMode.HIVE

	if self.Config.AlwaysEnabled and self:GetStage() == self.Stage.InGame then
		self.EnforcementPolicy = self:BuildEnforcementPolicy( self:GetVoteActionSettings() )
	else
		-- Nothing to enforce at startup.
		self.EnforcementPolicy = NoOpEnforcement()
	end

	self.dt.IsVoteForAutoShuffle = self.Config.AlwaysEnabled
	self.dt.IsAutoShuffling = self.Config.AlwaysEnabled

	self.TeamPreferences = {}
	self.LastAttemptedTeamJoins = {}

	self:BroadcastModuleEvent( "Initialise" )
	self.Enabled = true

	return true
end

function Plugin:ReceiveTeamPreference( Client, Data )
	local Preference = Data.PreferredTeam
	if Shine.IsPlayingTeam( Preference ) then
		self.TeamPreferences[ Client ] = Preference
	else
		self.TeamPreferences[ Client ] = nil
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "%s prefers team %s", Shine.GetClientInfo( Client ), self.TeamPreferences[ Client ] or 0 )
	end
end

do
	local function PlayerToString( Player )
		local Client = Player:GetClient()
		local NS2ID = Client:GetUserId()

		local Text = {}

		if Player:isa( "Commander" ) then
			Text[ 1 ] = "Commander - "
		else
			Text[ 1 ] = "Player - "
		end

		Text[ 2 ] = NS2ID

		if Client:GetIsVirtual() then
			Text[ 3 ] = " (Bot - "
			Text[ 4 ] = Player:GetName()
			Text[ 5 ] = ")"
		end

		return TableConcat( Text )
	end

	local function IsPlayer( Player )
		return Player.GetClient
	end

	function Plugin:AsLogOutput( Players )
		return Shine.Stream.Of( Players ):Filter( IsPlayer ):Map( PlayerToString ):AsTable()
	end

	local function DebugLogTeamMembers( Logger, self, Targets, TeamMembers )
		local TargetOutput = self:AsLogOutput( Targets )
		local TeamMemberOutput = {
			self:AsLogOutput( TeamMembers[ 1 ] ),
			self:AsLogOutput( TeamMembers[ 2 ] ),
			TeamPreferences = Shine.Stream( table.GetKeys( TeamMembers.TeamPreferences ) )
				:Filter( IsPlayer )
				:Map( function( Player )
					local PlayerAsString = PlayerToString( Player )
					local Preference = TeamMembers.TeamPreferences[ Player ]
					return StringFormat( "%s -> %s", PlayerAsString, Preference )
				end ):AsTable()
		}

		Logger:Debug( "Result of GetTargetsForSorting (IgnoreCommanders: %s):", self.Config.IgnoreCommanders )
		Logger:Debug( "Unassigned targets:\n%s", table.ToString( TargetOutput ) )
		Logger:Debug( "Assigned team members:\n%s", table.ToString( TeamMemberOutput ) )
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
		local IsEnforcingTeams = self.EnforcementPolicy:IsActive( self )

		local function AddTeamPreference( Player, Client, Preference )
			TeamMembers.TeamPreferences[ Player ] = Preference
			-- Track against thier client too as their player object will be changed
			-- if their team is changed.
			TeamMembers.TeamPreferences[ Client ] = Preference
		end

		local function SortPlayer( Player, Client, Commander, Pass )
			-- Do not shuffle clients that are in a spectator slot.
			if Client:GetIsSpectator() then return end

			local Team = Player:GetTeamNumber()
			if Team == 3 and self.Config.IgnoreSpectators then
				return
			end

			-- Don't move non-rookies on rookie servers.
			if IsRookieMode and not Player:GetIsRookie() then
				return
			end

			local IsImmune = Shine:HasAccess( Client, "sh_randomimmune" ) or Commander
			local IsPlayingTeam = Team == 1 or Team == 2
			-- Assume that if a player uses a team joining command (either walking into a TeamJoin entity or
			-- using the console) then they definitely want that team. Their persisted preference
			-- serves as a backup if they haven't yet chosen a team.
			local Preference = self.LastAttemptedTeamJoins[ Client ] or self.TeamPreferences[ Client ]

			-- Pass 1, put all immune players into team slots.
			-- This ensures they're picked last if there's a team imbalance at the end of sorting.
			-- It does not stop them from being swapped if it helps overall balance though.
			if Pass == 1 then
				if IsImmune then
					local TeamTable = TeamMembers[ Team ]
					if TeamTable then
						TeamTable[ #TeamTable + 1 ] = Player
						-- Either they have a set preference, or they joined the team they want.
						Preference = Preference or Team
						AddTeamPreference( Player, Client, Preference )
					end
				end

				return
			end

			-- Pass 2, put all non-immune players into team slots/target list.
			if IsImmune then return end

			if IsPlayingTeam then
				local TeamTable = TeamMembers[ Team ]
				TeamTable[ #TeamTable + 1 ] = Player
			else
				Targets[ #Targets + 1 ] = Player
			end

			AddTeamPreference( Player, Client, Preference )
		end

		local function IsClientAFK( Client )
			-- Consider players that have either been stationary for the appropriate amount of time,
			-- or have never been seen moving as AFK.
			return AFKKick:IsAFKFor( Client, self.Config.VoteSettings.AFKTimeInSeconds )
				or not AFKKick:HasClientMoved( Client )
		end

		local function AddPlayer( Player, Pass )
			if not Player then return end

			if Player.ResetScores and ResetScores then
				Player:ResetScores()
			end

			local Client = Player:GetClient()
			if not Shine:IsValidClient( Client ) then return end

			-- Bot and we don't want to deal with them, so kick them out.
			if Client:GetIsVirtual() and not self.Config.ApplyToBots then
				if Pass == 1 then
					Server.DisconnectClient( Client )
				end

				return
			end

			local Commander = Player:isa( "Commander" ) and self.Config.IgnoreCommanders

			if AFKEnabled then
				if Commander or not IsClientAFK( Client ) then
					-- Player is a commander or is not AFK, add them to the teams.
					SortPlayer( Player, Client, Commander, Pass )
				elseif Pass == 1 then
					-- Player is AFK, chuck them into the ready room.
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

		self.Logger:IfDebugEnabled( DebugLogTeamMembers, self, Targets, TeamMembers )

		return Targets, TeamMembers
	end
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
	local ModeFunction = self.ShufflingModes[ Mode ]
	ModeFunction( self, Gamerules, Targets, TeamMembers )

	local FunctionSource = DebugGetInfo( ModeFunction, "S" ).source
	local IsExpectedFunction = FunctionSource == "@lua/shine/extensions/voterandom/team_balance.lua"

	self.OptimisingTeams = false
	self.HasShuffledThisRound = true

	-- Remember who was on what team at the point of shuffling, so we can work out
	-- how close to the shuffled teams we are later.
	local TeamLookup = {}
	local NumPreferencesHeld = 0
	local NumPreferencesTotal = 0
	for i = 1, 2 do
		for j = 1, #TeamMembers[ i ] do
			local Player = TeamMembers[ i ][ j ]
			if Player.GetClient and Player:GetClient() then
				local Client = Player:GetClient()
				local SteamID = Client:GetUserId()
				TeamLookup[ SteamID ] = i

				-- Remember how many players got the team they wanted.
				local Preference = TeamMembers.TeamPreferences[ Client ]
				if IsType( Preference, "number" ) then
					NumPreferencesTotal = NumPreferencesTotal + 1
					if Preference == i then
						NumPreferencesHeld = NumPreferencesHeld + 1
					end
				end
			end
		end
	end

	TeamLookup.NumPreferencesHeld = NumPreferencesHeld
	TeamLookup.NumPreferencesTotal = NumPreferencesTotal
	-- If another mod has overridden the balance algorithm, tell players.
	TeamLookup.IsFunctionChanged = not IsExpectedFunction

	self.LastShuffleTeamLookup = TeamLookup
	self:ClearStatsCache()
end

function Plugin:GetOptimalTeamForPlayer( Player, Team1Players, Team2Players, SkillGetter )
	local Team1Skills = Shine.Stream( Team1Players ):Map( function( Player )
		return SkillGetter( Player, 1 ) or 0
	end ):AsTable()

	local Team2Skills = Shine.Stream( Team2Players ):Map( function( Player )
		return SkillGetter( Player, 2 ) or 0
	end ):AsTable()

	local StdDev1, Average1 = StandardDeviation( Team1Skills )
	local StdDev2, Average2 = StandardDeviation( Team2Skills )

	local function GetCostWithPlayerOnTeam( Skills, TeamNumber, AverageOther, StdDevOther )
		Skills[ #Skills + 1 ] = SkillGetter( Player, TeamNumber ) or 0

		local StdDev, Average = StandardDeviation( Skills )
		local AverageDiff = Abs( Average - AverageOther )
		local StdDiff = Abs( StdDev - StdDevOther )

		return self:GetCostFromDiff( AverageDiff, StdDiff )
	end

	local CostOn1 = GetCostWithPlayerOnTeam( Team1Skills, 1, Average2, StdDev2 )
	local CostOn2 = GetCostWithPlayerOnTeam( Team2Skills, 2, Average1, StdDev1 )

	if CostOn1 ~= CostOn2 then
		local TeamToJoin = 1
		if CostOn1 > CostOn2 then
			TeamToJoin = 2
		end

		self.Logger:Debug( "Picked team %d for %s (%s vs. %s)", TeamToJoin,
			Player, CostOn1, CostOn2 )

		return TeamToJoin
	end

	return nil
end

--[[
	Moves a single player onto a random team.
]]
function Plugin:JoinRandomTeam( Gamerules, Player )
	local Team1 = Gamerules:GetTeam( kTeam1Index ):GetNumPlayers()
	local Team2 = Gamerules:GetTeam( kTeam2Index ):GetNumPlayers()

	if Team1 < Team2 then
		Gamerules:JoinTeam( Player, 1 )
		return 1
	end

	if Team2 < Team1 then
		Gamerules:JoinTeam( Player, 2 )
		return 2
	end

	if self.LastShuffleMode == self.ShuffleMode.HIVE then
		local Team1Players = Gamerules.team1:GetPlayers()
		local Team2Players = Gamerules.team2:GetPlayers()

		local TeamToJoin = self:GetOptimalTeamForPlayer( Player,
			Team1Players, Team2Players, self.SkillGetters.GetHiveSkill )

		if TeamToJoin then
			Gamerules:JoinTeam( Player, TeamToJoin )
			return TeamToJoin
		end
	end

	local TeamNumber = Random() < 0.5 and 1 or 2
	Gamerules:JoinTeam( Player, TeamNumber )

	return TeamNumber
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
	-- Reset the block time when the round stops.
	if NewState == kGameState.NotStarted then
		self.VoteBlockTime = nil
	end

	if NewState ~= kGameState.Countdown then return end

	self:BroadcastModuleEvent( "GameStarting", Gamerules )
	self.EnforcementPolicy:OnStageChange( self.Stage.InGame )

	-- Block the vote after the set time.
	if self.Config.BlockAfterTime > 0 then
		self.VoteBlockTime = SharedTime() + self.Config.BlockAfterTime * 60
	end

	if not self.Config.AlwaysEnabled and not self.ShuffleOnNextRound then return end

	if self.Config.AlwaysEnabled then
		-- Reset any vote, as it cannot be used again until the round ends.
		self.Vote:Reset()

		-- If voted to disable auto-shuffle, do nothing.
		if self.SuppressAutoShuffle then return end
	end

	self.ShuffleOnNextRound = false

	if GetNumPlayers() < self.Config.MinPlayers then
		return
	end

	if self.DoneStartShuffle then return end

	self.DoneStartShuffle = true

	local OldValue = self.Config.IgnoreCommanders

	-- Force ignoring commanders.
	self.Config.IgnoreCommanders = true

	self:SendTranslatedNotify( nil, "AUTO_SHUFFLE", {
		ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
	} )
	self:ShuffleTeams()
	self:InitEnforcementPolicy( self:GetVoteActionSettings( self.QueuedStage ) )
	self.QueuedStage = nil

	self.Config.IgnoreCommanders = OldValue
end

function Plugin:EndGame( Gamerules, WinningTeam )
	self.LastAttemptedTeamJoins = {}
	self:SendNetworkMessage( nil, "TemporaryTeamPreference", {
		PreferredTeam = 0,
		Silent = true
	}, true )

	local Players, Count = GetAllPlayers()
	-- Reset the randomised state of all players.
	for i = 1, Count do
		local Player = Players[ i ]

		if Player then
			Player.ShineRandomised = nil
		end
	end

	self:BroadcastModuleEvent( "EndGame", Gamerules, WinningTeam, Players )
	self.EnforcementPolicy:OnStageChange( self.Stage.PreGame )

	self.DoneStartShuffle = false
	self.HasShuffledThisRound = false
	self.VoteBlockTime = nil

	-- If we're always enabled, we'll shuffle on round start.
	if self.Config.AlwaysEnabled then
		self.SuppressAutoShuffle = false
		self.dt.IsAutoShuffling = true
		self.dt.IsVoteForAutoShuffle = true

		self:DestroyTimer( self.RandomEndTimer )
		self.EnforcementPolicy = NoOpEnforcement()

		return
	end

	if self.ShuffleAtEndOfRound then
		self.ShuffleAtEndOfRound = false

		self:SimpleTimer( 15, function()
			local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
			if Enabled and MapVote:IsEndVote() then
				return
			end

			self:SendTranslatedNotify( nil, "PREVIOUS_VOTE_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )
			self:ShuffleTeams()
			self:InitEnforcementPolicy( self:GetVoteActionSettings( self.QueuedStage ) )
			self.QueuedStage = nil
		end )

		return
	end

	if not self.EnforcementPolicy:IsActive( self ) then
		return
	end

	-- Continue the existing policy (must be time based).
	self:SimpleTimer( 15, function()
		if not self.EnforcementPolicy:IsActive( self ) then return end

		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
		if not ( Enabled and MapVote:IsEndVote() ) then
			self:SendTranslatedNotify( nil, "PREVIOUS_VOTE_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )
			self:ShuffleTeams()
		end
	end )
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end

	local Gamestate = Gamerules:GetGameState()

	-- We'll do a mass balance, don't worry about them yet.
	if self.Config.AlwaysEnabled and Gamestate < kGameState.PreGame then return end

	-- Don't block them from going back to the ready room at the end of the round.
	if Gamestate == kGameState.Team1Won or Gamestate == kGameState.Team2Won
	or GameState == kGameState.Draw then return end

	if not self.EnforcementPolicy:IsActive( self ) then return end

	return self.EnforcementPolicy:JoinTeam( self, Gamerules, Player, NewTeam, Force )
end

function Plugin:ClientDisconnect( Client )
	self:BroadcastModuleEvent( "ClientDisconnect", Client )
	self.Vote:ClientDisconnect( Client )
	self:UpdateVoteCounters( self.Vote )
	self.TeamPreferences[ Client ] = nil

	if not self.ReconnectLogTimeout then return end
	if SharedTime() > self.ReconnectLogTimeout then return end

	self.ReconnectingClients[ Client:GetUserId() ] = true
end

function Plugin:ClientConnect( Client )
	self:UpdateVoteCounters( self.Vote )

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
	local PlayerCount = self:GetPlayerCountForVote()
	return Ceil( PlayerCount * self.Config.PercentNeeded )
end

function Plugin:GetStartFailureMessage()
	return "ERROR_CANNOT_START", { ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ] }
end

function Plugin:EvaluateConstraints( NumPlayers, TeamStats )
	local NumOnTeam1 = #TeamStats[ 1 ].Skills
	local NumOnTeam2 = #TeamStats[ 2 ].Skills
	local NumPlayersOnPlayingTeams = NumOnTeam1 + NumOnTeam2
	local FractionOfPlayersOnTeams = NumPlayersOnPlayingTeams / NumPlayers

	if FractionOfPlayersOnTeams < self.Config.VoteConstraints.MinPlayerFractionToConstrain then
		-- Not enough players on playing teams to apply constraints.
		self.Logger:Debug( "Permitting vote as only %s of all players are on teams.", FractionOfPlayersOnTeams )
		return true
	end

	if Abs( NumOnTeam1 - NumOnTeam2 ) > 1 then
		-- Imbalanced number of players on teams, permit a shuffle.
		self.Logger:Debug( "Permitting vote as team counts are uneven: %s vs. %s", NumOnTeam1, NumOnTeam2 )
		return true
	end

	local AverageDiff = Abs( TeamStats[ 1 ].Average - TeamStats[ 2 ].Average )
	if AverageDiff >= self.Config.VoteConstraints.MinAverageDiffToAllowShuffle then
		-- Teams are far enough apart in average skill to allow the vote.
		self.Logger:Debug( "Permitting vote as average difference is: %s", AverageDiff )
		return true
	end

	local StdDiff = Abs( TeamStats[ 1 ].StandardDeviation - TeamStats[ 2 ].StandardDeviation )
	local MinStdDiff = self.Config.VoteConstraints.MinStandardDeviationDiffToAllowShuffle
	if MinStdDiff > 0 and StdDiff >= MinStdDiff then
		-- Teams are far enough apart in standard deviation of skill to allow the vote.
		self.Logger:Debug( "Permitting vote as standard deviation difference is: %s", StdDiff )
		return true
	end

	self.Logger:Debug( "Rejecting vote as teams are sufficiently balanced (%s of all players on teams, %s on team 1, %s on team 2, %s average diff, %s standard deviation diff)",
		FractionOfPlayersOnTeams, NumOnTeam1, NumOnTeam2, AverageDiff, StdDiff )

	-- Sufficient players on playing teams, not imbalanced and average and standard deviations
	-- are close enough to be considered balanced so reject the vote.
	return false
end

function Plugin:IsVoteAllowed()
	local Allow, Error, TranslationKey, Args = Shine.Hook.Call( "OnVoteStart", "random" )
	if Allow == false then
		return false, TranslationKey, Args
	end
	return true
end

function Plugin:CanStartVote()
	if self:GetStage() == self.Stage.InGame and self.Config.AlwaysEnabled then
		-- Disabling/enabling auto shuffle should only be possible before a round starts.
		return false, self:GetStartFailureMessage()
	end

	if self.VoteBlockTime and self.VoteBlockTime < SharedTime() then
		return false, "ERROR_ROUND_TOO_FAR"
	end

	do
		local Allowed, Err, Args = self:IsVoteAllowed()
		if not Allowed then
			return Allowed, Err, Args
		end
	end

	if self:GetPlayerCountForVote() < self.Config.MinPlayers then
		return false, "ERROR_NOT_ENOUGH_PLAYERS"
	end

	if self.NextVote >= SharedTime() then
		return false, self:GetStartFailureMessage()
	end

	if self.ShuffleOnNextRound or self.ShuffleAtEndOfRound then
		return false, "ERROR_ALREADY_ENABLED", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
	end

	if self.Config.BalanceMode == self.ShuffleMode.HIVE
	and not self:EvaluateConstraints( GetNumPlayers(), self:GetTeamStats() ) then
		return false, "ERROR_CONSTRAINTS"
	end

	return true
end

--[[
	Adds a player's vote to the counter.
]]
function Plugin:AddVote( Client )
	if not Client then Client = "Console" end

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

Plugin.Stage = table.AsEnum{
	"PreGame", "InGame"
}

function Plugin:GetStage()
	local Gamerules = GetGamerules()
	if not Gamerules then return self.Stage.PreGame end

	local GameState = Gamerules:GetGameState()
	local IsInActiveRound = GameState >= kGameState.Countdown and GameState <= kGameState.Started
	return IsInActiveRound and self.Stage.InGame or self.Stage.PreGame
end

function Plugin:GetVoteActionSettings( Stage )
	return self.Config.VotePassActions[ Stage or self:GetStage() ]
end

Plugin.ShufflePolicyActions = {
	-- Shuffle teams right when the vote passes.
	[ Plugin.ShufflePolicy.INSTANT ] = function( self )
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

		self:InitEnforcementPolicy( self:GetVoteActionSettings() )

		if Started then
			Gamerules:ResetGame()
		end
	end,
	-- Queue a shuffle for the start of the next round.
	[ Plugin.ShufflePolicy.NEXT_ROUND ] = function( self )
		self:SendTranslatedNotify( nil, "TEAMS_FORCED_NEXT_ROUND", {
			ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
		} )
		self.ShuffleOnNextRound = true
		self.QueuedStage = self:GetStage()
		self.Logger:Debug( "Queued shuffle for the start of the next round." )
	end,
	-- Queue a shuffle for either the start of the next round, or the end of this one.
	[ Plugin.ShufflePolicy.END_OF_PERIOD ] = function( self )
		if self:GetStage() == self.Stage.PreGame then
			return self.ShufflePolicyActions[ self.ShufflePolicy.NEXT_ROUND ]( self )
		end

		self.ShuffleAtEndOfRound = true
		self.QueuedStage = self:GetStage()
		self:SendTranslatedNotify( nil, "TEAMS_FORCED_END_OF_ROUND", {
			ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
		} )
		self.Logger:Debug( "Queued shuffle for the end of the current round." )
	end
}

Plugin.EnforcementPolicies = {
	-- Do not enforce anything.
	[ Plugin.EnforcementDurationType.NONE ] = function( self, Settings )
		return NoOpEnforcement()
	end,
	-- Enforce teams for the given duration.
	[ Plugin.EnforcementDurationType.TIME ] = function( self, Settings )
		local Duration = Settings.DurationInMinutes * 60
		if Duration > 5 then
			self.Logger:Debug( "Enforcement will end in %d seconds", Duration )
			return DurationBasedEnforcement( Duration, Settings.EnforcementPolicy )
		end

		-- Not enough of a duration to bother with.
		return NoOpEnforcement()
	end,
	-- Enforce teams until the game stage changes.
	[ Plugin.EnforcementDurationType.PERIOD ] = function( self, Settings )
		return PeriodBasedEnforcement( self:GetStage(), Settings.EnforcementPolicy )
	end
}

function Plugin:BuildEnforcementPolicy( Settings )
	if #Settings.EnforcementPolicy == 0 then
		self.Logger:Debug( "No enforcement policies configured, disabling enforcement." )
		-- No policies configured, so nothing to enforce.
		return self.EnforcementPolicies[ self.EnforcementDurationType.NONE ]( self, Settings )
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Applying enforcement policies [ %s ] with duration type %s",
			Shine.Stream( Settings.EnforcementPolicy ):Concat( ", " ), Settings.EnforcementDurationType )
	end

	return self.EnforcementPolicies[ Settings.EnforcementDurationType ]( self, Settings )
end

function Plugin:InitEnforcementPolicy( Settings )
	self:DestroyTimer( self.RandomEndTimer )

	self.EnforcementPolicy = self:BuildEnforcementPolicy( Settings )
	self.EnforcementPolicy:Announce( self )
	return self.EnforcementPolicy
end

--[[
	Applies the configured shuffle settings, based on the current game stage.
]]
function Plugin:ApplyRandomSettings()
	self.RandomApplied = true
	self:SimpleTimer( 0, function()
		self.RandomApplied = false
	end )

	if self.Config.AlwaysEnabled then
		self.SuppressAutoShuffle = not self.SuppressAutoShuffle
		self.dt.IsAutoShuffling = not self.SuppressAutoShuffle

		local Key = self.SuppressAutoShuffle and "AUTO_SHUFFLE_DISABLED" or "AUTO_SHUFFLE_ENABLED"
		self:SendTranslatedNotify( nil, Key, {
			ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
		} )
	else
		local Settings = self:GetVoteActionSettings()
		self.ShufflePolicyActions[ Settings.ShufflePolicy ]( self )
	end

	self.NextVote = SharedTime() + self.Config.VoteCooldownInMinutes * 60
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
					local Key = "PLAYER_VOTED"
					if self.Config.AlwaysEnabled then
						Key = self.SuppressAutoShuffle and "PLAYER_VOTED_ENABLE_AUTO"
							or "PLAYER_VOTED_DISABLE_AUTO"
					end

					self:SendTranslatedNotify( nil, Key, {
						ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ],
						VotesNeeded = VotesNeeded,
						PlayerName = PlayerName
					} )
				else
					local Key = "PLAYER_VOTED_PRIVATE"
					if self.Config.AlwaysEnabled then
						Key = self.SuppressAutoShuffle and "PLAYER_VOTED_ENABLE_AUTO_PRIVATE"
							or "PLAYER_VOTED_DISABLE_AUTO_PRIVATE"
					end

					self:SendTranslatedNotify( Client, Key, {
						ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ],
						VotesNeeded = VotesNeeded
					} )
				end

				self:UpdateVoteCounters( self.Vote )
				self:NotifyVoted( Client )
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
			self.ShufflePolicyActions[ self.ShufflePolicy.INSTANT ]( self )

			self:SendTranslatedMessage( Client, "ENABLED_TEAMS", {
				ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
			} )
		else
			self.Vote:Reset()

			if self.Config.AlwaysEnabled then
				self.SuppressAutoShuffle = true
				self.dt.IsAutoShuffling = false
			end

			self.ShuffleOnNextRound = false
			self.ShuffleAtEndOfRound = false
			self:DestroyTimer( self.RandomEndTimer )
			self.EnforcementPolicy = NoOpEnforcement()

			self:SendTranslatedNotify( nil, "DISABLED_TEAMS", {
				ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
			} )
		end
	end
	local ForceRandomCommand = self:BindCommand( "sh_enablerandom",
		{ "enablerandom", "enableshuffle", "forceshuffle" }, ForceRandomTeams )
	ForceRandomCommand:AddParam{ Type = "boolean", Optional = true,
		Default = true }
	ForceRandomCommand:Help( "Enables (and applies) or disables forcing shuffled teams." )

	self:BindCommandAlias( "sh_enablerandom", "sh_forceshuffle" )

	local function ViewTeamStats( Client )
		if self.Config.BalanceMode ~= self.ShuffleMode.HIVE then
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
				"Last shuffle was %s ago. %d/%d player(s) match their team from the last shuffle.",
				string.TimeToString( SharedTime() - self.LastShuffleTime ),
				TeamStats.NumMatchingTeams or 0,
				TeamStats.TotalPlayers or 0 )
			Message[ #Message + 1 ] = StringFormat( "%d/%d player(s) were placed on their preferred team.",
				TeamStats.NumPreferencesHeld or 0,
				TeamStats.NumPreferencesTotal or 0 )
			if TeamStats.IsFunctionChanged then
				-- If you're altering the algorithm, please don't try to suppress this.
				-- It's important for players to know when the shuffle algorithm is different so
				-- it's clear who to report problems to.
				Message[ #Message + 1 ] = "Another mod has altered the shuffle algorithm, results may be different to other servers."
			end
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

Shine.LoadPluginFile( "voterandom", "local_stats.lua" )
Shine.LoadPluginModule( "vote.lua" )
Shine.LoadPluginModule( "logger.lua" )
