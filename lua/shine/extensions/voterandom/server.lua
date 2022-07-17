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
local GetMaxPlayers = Server.GetMaxPlayers
local GetNumPlayers = Shine.GetHumanPlayerCount
local GetNumSpectators = Server.GetNumSpectators
local GetClientForPlayer = Shine.GetClientForPlayer
local IsType = Shine.IsType
local Max = math.max
local Random = math.random
local SharedTime = Shared.GetTime
local StandardDeviation = math.StandardDeviation
local StringFormat = string.format
local TableConcat = table.concat
local tostring = tostring

local Plugin, PluginName = ...
Plugin.Version = "2.12"
Plugin.PrintName = "Shuffle"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteRandom.json"

Plugin.RandomEndTimer = "VoteRandomTimer"

Plugin.ShufflePolicy = table.AsEnum{
	"INSTANT", "NEXT_ROUND", "END_OF_PERIOD"
}
Plugin.EnforcementDurationType = table.AsEnum{
	"NONE", "TIME", "PERIOD"
}
Plugin.EnforcementPolicyType = table.AsEnum{
	"BLOCK_TEAMS", "ASSIGN_PLAYERS"
}
Plugin.TeamPreferenceWeighting = table.AsEnum{
	"NONE", "LOW", "MEDIUM", "HIGH"
}

-- These are derived from simulated optimisation results.
Plugin.TeamPreferenceWeightingValues = {
	[ Plugin.TeamPreferenceWeighting.NONE ] = 0,
	[ Plugin.TeamPreferenceWeighting.LOW ] = 2,
	[ Plugin.TeamPreferenceWeighting.MEDIUM ] = 3,
	[ Plugin.TeamPreferenceWeighting.HIGH ] = 5
}
Plugin.PlayWithFriendsWeightingValues = {
	[ Plugin.TeamPreferenceWeighting.NONE ] = 0,
	[ Plugin.TeamPreferenceWeighting.LOW ] = 25,
	[ Plugin.TeamPreferenceWeighting.MEDIUM ] = 50,
	[ Plugin.TeamPreferenceWeighting.HIGH ] = 100
}

Plugin.MODE_RANDOM = Plugin.ShuffleMode.RANDOM
Plugin.MODE_SCORE = Plugin.ShuffleMode.SCORE
Plugin.MODE_ELO = Plugin.ShuffleMode.INVALID
Plugin.MODE_KDR = Plugin.ShuffleMode.KDR
Plugin.MODE_HIVE = Plugin.ShuffleMode.HIVE

local ModeStrings = Plugin.ModeStrings

Plugin.DefaultConfig = {
	BlockUntilSecondsIntoMap = 0, -- Time in seconds to block votes for after a map change.
	BlockAfterRoundTimeInMinutes = 2, -- Time in minutes after round start to block the vote. 0 to disable blocking.
	VoteCooldownInMinutes = 1, -- Cooldown time before another vote can be made.
	VoteTimeoutInSeconds = 60, -- Time after the last vote before the vote resets.
	NotifyOnVote = true, -- Should all players be told through the chat when a vote is cast?
	ApplyToBots = false, -- Should bots be shuffled, or removed?
	BlockBotsAfterShuffle = true, -- Whether filler bots should be blocked after a shuffle removes them.

	BalanceMode = Plugin.ShuffleMode.HIVE, -- How should teams be balanced?
	FallbackMode = Plugin.ShuffleMode.KDR, -- Which method should be used if Hive fails?

	RemoveAFKPlayersFromTeams = true, -- Should the plugin remove AFK players from teams when shuffling?
	IgnoreCommanders = true, -- Should the plugin ignore commanders when switching?
	IgnoreSpectators = true, -- Should the plugin ignore spectators in player slots when switching?
	AutoShuffleAtRoundStart = true, -- Should the plugin be always forcing each round?
	EndOfRoundShuffleDelayInSeconds = 30, -- How long after a round end before auto-shuffling if enforcement is still active.

	ReconnectLogTimeInSeconds = 0, -- How long (in seconds) after a shuffle to log reconnecting players for?
	HighlightTeamSwaps = false, -- Should players swapping teams be highlighted on the scoreboard?
	DisplayStandardDeviations = false, -- Should the scoreboard show each team's standard deviation of skill?

	BalanceModeConfig = {
		[ Plugin.ShuffleMode.HIVE ] = {
			UseTeamSkill = true,
			UseCommanderSkill = true,
			-- Whether to blend the commander and field skill values for an alien commander to account for them being
			-- out of the hive for a significant amount of time during a round.
			BlendAlienCommanderAndFieldSkills = false
		}
	},

	VoteConstraints = {
		PreGame = {
			-- Minimum number of players on the server to enable voting.
			MinPlayers = 10,

			-- Fraction of players that need to vote before a shuffle is performed.
			FractionNeededToPass = 0.6,

			-- When the number of players on playing teams is greater-equal this fraction
			-- of the total players on the server, apply skill difference constraints.
			MinPlayerFractionToConstrainSkillDiff = 0.9,

			-- The minimum difference in average skill required to permit shuffling.
			-- A value of 0 will permit all votes.
			MinAverageDiffToAllowShuffle = 75,

			-- The minimum difference in standard deviation of skill required to permit shuffling.
			-- Must be greater than 0 to enable checking.
			MinStandardDeviationDiffToAllowShuffle = 0
		},
		InGame = {
			MinPlayers = 10,
			FractionNeededToPass = 0.75,
			MinPlayerFractionToConstrainSkillDiff = 0.9,
			MinAverageDiffToAllowShuffle = 100,
			MinStandardDeviationDiffToAllowShuffle = 0,

			-- How long to wait after the round starts before transitioning vote constraints/pass actions to "InGame".
			StartOfRoundGraceTimeInSeconds = 0
		}
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
			EnforcementPolicy = {
				{
					Type = Plugin.EnforcementPolicyType.BLOCK_TEAMS,
					-- If there are less than this many players, this policy will not be applied.
					MinPlayers = 0,
					-- If there are more than this many players (and this is not 0), this policy will not be applied.
					MaxPlayers = 0
				},
				{
					Type = Plugin.EnforcementPolicyType.ASSIGN_PLAYERS,
					MinPlayers = 0,
					MaxPlayers = 0
				}
			},
			DurationInMinutes = 15
		},
		-- What to do when a vote passes during an active game.
		InGame = {
			ShufflePolicy = Plugin.ShufflePolicy.INSTANT,
			EnforcementDurationType = Plugin.EnforcementDurationType.TIME,
			EnforcementPolicy = {
				{
					Type = Plugin.EnforcementPolicyType.BLOCK_TEAMS,
					MinPlayers = 0,
					MaxPlayers = 0
				},
				{
					Type = Plugin.EnforcementPolicyType.ASSIGN_PLAYERS,
					MinPlayers = 0,
					MaxPlayers = 0
				}
			},
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
				Config.TeamPreferences.CostWeighting = Plugin.TeamPreferenceWeighting.MEDIUM
			end
		end
	},
	{
		VersionTo = "2.5",
		Apply = Shine.Migrator()
			:RenameField( "BlockAfterTime", "BlockAfterRoundTimeInMinutes" )
			:RenameField( "VoteTimeout", "VoteTimeoutInSeconds" )
			:RenameField( "ReconnectLogTime", "ReconnectLogTimeInSeconds" )
	},
	{
		VersionTo = "2.6",
		Apply = Shine.Migrator()
			:AddField( { "TeamPreferences", "PlayWithFriendsWeighting" }, Plugin.TeamPreferenceWeighting.MEDIUM )
			:AddField( { "TeamPreferences", "MaxFriendGroupSize" }, 4 )
	},
	{
		VersionTo = "2.7",
		Apply = Shine.Migrator()
			:AddField( { "TeamPreferences", "FriendGroupInviteDurationInSeconds" }, 15 )
			:AddField( { "TeamPreferences", "FriendGroupInviteCooldownInSeconds" }, 15 )
	},
	{
		VersionTo = "2.8",
		Apply = Shine.Migrator()
			:ApplyAction( function( Config )
				local function ConvertPolicy( Policy )
					return {
						Type = Policy,
						MinPlayers = 0,
						MaxPlayers = 0
					}
				end
				local function ConvertPolicyList( List )
					if not IsType( List, "table" ) then return List end

					return Shine.Stream( List ):Distinct():Map( ConvertPolicy ):AsTable()
				end

				Config.VotePassActions.PreGame.EnforcementPolicy = ConvertPolicyList(
					Config.VotePassActions.PreGame.EnforcementPolicy
				)
				Config.VotePassActions.InGame.EnforcementPolicy = ConvertPolicyList(
					Config.VotePassActions.InGame.EnforcementPolicy
				)
			end )
			:RenameField(
				{ "VoteConstraints", "MinPlayerFractionToConstrain" },
				{ "VoteConstraints", "PreGame", "MinPlayerFractionToConstrainSkillDiff" }
			)
			:RenameField(
				{ "VoteConstraints", "MinAverageDiffToAllowShuffle" },
				{ "VoteConstraints", "PreGame", "MinAverageDiffToAllowShuffle" }
			)
			:RenameField(
				{ "VoteConstraints", "MinStandardDeviationDiffToAllowShuffle" },
				{ "VoteConstraints", "PreGame", "MinStandardDeviationDiffToAllowShuffle" }
			)
			:RenameField( "PercentNeeded", { "VoteConstraints", "PreGame", "FractionNeededToPass" } )
			:RenameField( "MinPlayers", { "VoteConstraints", "PreGame", "MinPlayers" } )
			:CopyField( { "VoteConstraints", "PreGame" }, { "VoteConstraints", "InGame" } )
			:AddField(
				{ "VoteConstraints", "InGame", "StartOfRoundGraceTimeInSeconds" },
				Plugin.DefaultConfig.VoteConstraints.InGame.StartOfRoundGraceTimeInSeconds
			)
			:RenameField( "AlwaysEnabled", "AutoShuffleAtRoundStart" )
			:AddField( "EndOfRoundShuffleDelayInSeconds", Plugin.DefaultConfig.EndOfRoundShuffleDelayInSeconds )
			:AddField( "BlockBotsAfterShuffle", Plugin.DefaultConfig.BlockBotsAfterShuffle )
	},
	{
		VersionTo = "2.9",
		Apply = Shine.Migrator()
			:AddField( "BalanceModeConfig", Plugin.DefaultConfig.BalanceModeConfig )
	},
	{
		VersionTo = "2.10",
		Apply = Shine.Migrator()
			:AddField( { "TeamPreferences", "FriendGroupRestoreTimeoutSeconds" }, 300 )
	},
	{
		VersionTo = "2.11",
		Apply = Shine.Migrator()
			:AddField( { "VoteSettings", "ConsiderSpectatorsDuringActiveRound" }, true )
	},
	{
		VersionTo = "2.12",
		Apply = Shine.Migrator()
			:AddField( { "BalanceModeConfig", Plugin.ShuffleMode.HIVE, "BlendAlienCommanderAndFieldSkills" }, false )
	}
}

do
	local Validator = Shine.Validator()

	Validator:CheckTypesAgainstDefault( "BalanceModeConfig", Plugin.DefaultConfig.BalanceModeConfig )
	for i = 1, #Plugin.ShuffleMode do
		local Mode = Plugin.ShuffleMode[ i ]
		local DefaultConfigForMode = Plugin.DefaultConfig.BalanceModeConfig[ Mode ]
		if DefaultConfigForMode then
			Validator:CheckTypesAgainstDefault( "BalanceModeConfig."..Mode, DefaultConfigForMode )
		end
	end

	Validator:CheckTypesAgainstDefault( "VoteConstraints", Plugin.DefaultConfig.VoteConstraints )
	Validator:CheckTypesAgainstDefault( "VoteConstraints.PreGame", Plugin.DefaultConfig.VoteConstraints.PreGame )
	Validator:CheckTypesAgainstDefault( "VoteConstraints.InGame", Plugin.DefaultConfig.VoteConstraints.InGame )

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
	}, Validator.InEnum( Plugin.EnforcementDurationType, Plugin.EnforcementDurationType.TIME ) )
	Validator:AddFieldRules(
		{
			"VotePassActions.PreGame.EnforcementPolicy",
			"VotePassActions.InGame.EnforcementPolicy"
		},
		Validator.AllValuesSatisfy(
			Validator.ValidateField( "Type", Validator.InEnum( Plugin.EnforcementPolicyType ), {
				DeleteIfFieldInvalid = true
			} ),
			Validator.ValidateField( "MinPlayers", Validator.IsType( "number", 0 ) ),
			Validator.ValidateField( "MaxPlayers", Validator.IsType( "number", 0 ) )
		)
	)
	Validator:AddFieldRules( {
		"VotePassActions.PreGame.DurationInMinutes",
		"VotePassActions.InGame.DurationInMinutes"
	}, Validator.IsType( "number", 15 ) )

	Validator:AddFieldRule( "BalanceMode", Validator.InEnum( Plugin.ShuffleMode, Plugin.ShuffleMode.HIVE ) )
	Validator:AddFieldRule( "FallbackMode", Validator.InEnum( Plugin.ShuffleMode, Plugin.ShuffleMode.KDR ) )
	Validator:AddFieldRule( "ReconnectLogTimeInSeconds", Validator.Min( 0 ) )

	Plugin.ConfigValidator = Validator
end

local EnforcementPolicy = Shine.TypeDef()
function EnforcementPolicy:Init( Policies )
	local PoliciesByType = {}
	for i = 1, #Policies do
		local Policy = Policies[ i ]
		PoliciesByType[ Policy.Type ] = Policy
	end

	self.Policies = PoliciesByType

	return self
end

function EnforcementPolicy:IsActive()
	return false
end

function EnforcementPolicy:OnStageChange( Stage )

end

function EnforcementPolicy:Announce( Plugin )

end

function EnforcementPolicy:IsPolicyEnforced( Policy, PlayerCount )
	local Options = self.Policies[ Policy ]
	if not Options then
		return false
	end

	return PlayerCount >= Options.MinPlayers and ( Options.MaxPlayers == 0 or PlayerCount <= Options.MaxPlayers )
end

function EnforcementPolicy:JoinTeam( Plugin, Gamerules, Player, NewTeam, Force )
	local Client = GetClientForPlayer( Player )
	if not Client then return false end

	local Immune = Client:GetIsVirtual() or Shine:HasAccess( Client, "sh_randomimmune" )
	if Immune then return end

	local PlayerCount = Shine.GetHumanPlayerCount()
	local Team = Player:GetTeamNumber()
	local OnPlayingTeam = Shine.IsPlayingTeam( Team )

	local NumTeam1 = Gamerules.team1:GetNumPlayers()
	local NumTeam2 = Gamerules.team2:GetNumPlayers()

	local ImbalancedTeams = Abs( NumTeam1 - NumTeam2 ) >= 2

	-- Do not allow cheating the system.
	if OnPlayingTeam and self:IsPolicyEnforced( Plugin.EnforcementPolicyType.BLOCK_TEAMS, PlayerCount ) then
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

	if ( NumTeam1 == 0 and NumTeam2 == 0 )
	or not self:IsPolicyEnforced( Plugin.EnforcementPolicyType.ASSIGN_PLAYERS, PlayerCount ) then
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

function DurationBasedEnforcement:IsActive( Plugin, TimeToCheck )
	return ( TimeToCheck or SharedTime() ) < self.EndTime
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

Shine.LoadPluginFile( PluginName, "team_balance.lua", Plugin, PluginName )
Shine.LoadPluginFile( PluginName, "friend_groups.lua", Plugin, PluginName )

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
			Event.Hook( Entry.Event, self:WrapCallback( function( Client )
				local Gamerules = GetGamerules()
				if not Gamerules or Gamerules:GetGameStarted() then return end
				if self.LastAttemptedTeamJoins[ Client ] == Team then return end

				if self.Logger:IsDebugEnabled() then
					self.Logger:Debug( "%s has chosen team %s (has persistent preference: %s)",
						Shine.GetClientInfo( Client ), Team, self.TeamPreferences[ Client ] or "none" )
				end

				self.LastAttemptedTeamJoins[ Client ] = Team

				-- Don't display a message if voting is disabled (e.g. end of map vote).
				local Silent = not self:IsVoteAllowed()

				self:SendNetworkMessage( Client, "TemporaryTeamPreference", {
					PreferredTeam = Team or 0,
					Silent = Silent
				}, true )

				self:UpdateFriendGroupTeamPreference( Client, Silent )
			end ) )
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
	self:BroadcastModuleEvent( "Initialise" )

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

	self.NextVote = self.Config.BlockUntilSecondsIntoMap

	local function GetVotesNeeded()
		return self:GetVotesNeeded()
	end

	local function OnVotePassed()
		self:ApplyRandomSettings()
	end

	self.Vote = Shine:CreateVote( GetVotesNeeded, self:WrapCallback( OnVotePassed ) )
	self:SetupVoteTimeout( self.Vote, self.Config.VoteTimeoutInSeconds )
	function self.Vote.OnReset()
		self:ResetVoteCounters()
	end

	self.ShuffleOnNextRound = false
	self.ShuffleAtEndOfRound = false
	self.HasShuffledThisRound = false
	self.SuppressAutoShuffle = false

	self.dt.HighlightTeamSwaps = self.Config.HighlightTeamSwaps
	self.dt.DisplayStandardDeviations = self.Config.DisplayStandardDeviations
		and BalanceMode == self.ShuffleMode.HIVE and not self:IsPerTeamSkillEnabled()
		and not self:IsCommanderSkillEnabled()

	if self.Config.AutoShuffleAtRoundStart and self:GetStage() == self.Stage.InGame then
		self.EnforcementPolicy = self:BuildEnforcementPolicy( self:GetVoteActionSettings() )
	else
		-- Nothing to enforce at startup.
		self.EnforcementPolicy = NoOpEnforcement()
	end

	self.dt.IsVoteForAutoShuffle = self.Config.AutoShuffleAtRoundStart
	self.dt.IsAutoShuffling = self.Config.AutoShuffleAtRoundStart

	self.TeamPreferences = {}
	self.LastAttemptedTeamJoins = {}

	self.FriendGroups = {}
	self.FriendGroupsBySteamID = {}
	self.FriendGroupConfigBySteamID = {}
	self.FriendGroupInvitesBySteamID = {}
	self.FriendGroupInviteDelaysBySteamID = {}

	self:LoadFriendGroups()

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

	self:UpdateFriendGroupTeamPreference( Client )

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
				end ):AsTable(),
			PlayerGroups = Shine.Stream.Of( TeamMembers.PlayerGroups )
				:Map( function( Group )
					return {
						Players = self:AsLogOutput( Group.Players )
					}
				end )
				:AsTable()
		}

		Logger:Debug( "Result of GetTargetsForSorting (IgnoreCommanders: %s):", self.Config.IgnoreCommanders )
		Logger:Debug( "Unassigned targets:\n%s", table.ToString( TargetOutput ) )
		Logger:Debug( "Assigned team members:\n%s", table.ToString( TeamMemberOutput ) )
	end

	function Plugin:IsClientAFK( AFKKick, Client )
		-- Consider players that have either been stationary for the appropriate amount of time,
		-- or have never been seen moving as AFK.
		return AFKKick:IsAFKFor( Client, self.Config.VoteSettings.AFKTimeInSeconds )
			or not AFKKick:HasClientMoved( Client )
	end

	function Plugin:IsRookieModeEnabled( Gamerules )
		return Gamerules.gameInfo and Gamerules.gameInfo:GetRookieMode()
	end

	function Plugin:GetTeamPreference( Client )
		return self.LastAttemptedTeamJoins[ Client ] or self.TeamPreferences[ Client ]
	end

	local function KickBot( Client )
		if Client.bot and Client.bot.Disconnect then
			Client.bot:Disconnect()
		else
			Server.DisconnectClient( Client )
		end
	end

	function Plugin:GetMaxPlayers()
		return GetMaxPlayers()
	end

	function Plugin:RemoveBotsIfNeeded( Targets, TeamMembers )
		local MaxPlayers = self:GetMaxPlayers()
		local NumCandidatePlayers = #Targets + #TeamMembers[ 1 ] + #TeamMembers[ 2 ]
		if NumCandidatePlayers <= MaxPlayers or not self.Config.ApplyToBots then return end

		self.Logger:Debug(
			"Number of potential players (%s) exceeds player slot count (%s), attempting to remove bots...",
			NumCandidatePlayers,
			MaxPlayers
		)

		-- Too many players, remove bots to make room.
		-- This can happen if there's lots of players in the ready room and not enough in the playing teams, which
		-- means there'll be bots on each team that end up included in the shuffle.
		local function RemoveBotPlayerIfNeeded( Player )
			local Client = Player:GetClient()
			if
				NumCandidatePlayers > MaxPlayers and Client:GetIsVirtual() and
				-- Leave commander bots alone, they're presumably added intentionally unlike player bots.
				not self.IsPlayerCommander( Player, Client )
			then
				if self.Logger:IsDebugEnabled() then
					self.Logger:Debug(
						"Kicking bot %s to make room for human players...",
						PlayerToString( Player )
					)
				end

				NumCandidatePlayers = NumCandidatePlayers - 1
				KickBot( Client )

				return false
			end

			return true
		end

		-- First try removing bots from the targets (there shouldn't be any, but just in case).
		Shine.Stream( Targets ):Filter( RemoveBotPlayerIfNeeded )

		-- If not enough bots were removed, try to remove them from playing teams.
		Shine.Stream( TeamMembers[ 1 ] ):Filter( RemoveBotPlayerIfNeeded )
		Shine.Stream( TeamMembers[ 2 ] ):Filter( RemoveBotPlayerIfNeeded )
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
		local IsRookieMode = self:IsRookieModeEnabled( Gamerules )

		local function AddTeamPreference( Player, Client, Preference )
			TeamMembers.TeamPreferences[ Player ] = Preference
			-- Track against thier client too as their player object will be changed
			-- if their team is changed.
			TeamMembers.TeamPreferences[ Client ] = Preference
		end

		local PlayersToBeShuffled = {}

		local function SortPlayer( Player, Client, IsCommander, Pass )
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

			local IsImmune = IsCommander or Shine:HasAccess( Client, "sh_randomimmune" )
			local IsPlayingTeam = Team == 1 or Team == 2
			-- Assume that if a player uses a team joining command (either walking into a TeamJoin entity or
			-- using the console) then they definitely want that team. Their persisted preference
			-- serves as a backup if they haven't yet chosen a team.
			local Preference = self:GetTeamPreference( Client )

			-- Pass 1, put all immune players into team slots.
			-- This ensures they're picked last if there's a team imbalance at the end of sorting.
			-- It does not stop them from being swapped if it helps overall balance though.
			if Pass == 1 then
				if IsImmune then
					local TeamTable = TeamMembers[ Team ]
					if TeamTable then
						PlayersToBeShuffled[ Player ] = true
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

			PlayersToBeShuffled[ Player ] = true

			AddTeamPreference( Player, Client, Preference )
		end

		local function AddPlayer( Player, Pass )
			if not Player then return end

			if Player.ResetScores and ResetScores then
				Player:ResetScores()
			end

			local Client = Player:GetClient()
			if not Shine:IsValidClient( Client ) then return end

			local IsCommander = self.IsPlayerCommander( Player, Client ) and self.Config.IgnoreCommanders

			-- Bot and we don't want to deal with them, so kick them out.
			if Client:GetIsVirtual() and not IsCommander and not self.Config.ApplyToBots then
				if Pass == 1 then
					KickBot( Client )
				end
				return
			end

			if AFKEnabled and self.Config.RemoveAFKPlayersFromTeams then
				if IsCommander or not self:IsClientAFK( AFKKick, Client ) then
					-- Player is a commander or is not AFK, add them to the teams.
					SortPlayer( Player, Client, IsCommander, Pass )
				elseif Pass == 1 then
					-- Player is AFK, chuck them into the ready room.
					local Team = Player:GetTeamNumber()
					-- Only move players on playing teams...
					if Team == 1 or Team == 2 then
						if self.Logger:IsDebugEnabled() then
							self.Logger:Debug(
								"Moving %s to the ready room as they are AFK.",
								Shine.GetClientInfo( Client )
							)
						end
						Gamerules:JoinTeam( Player, 0, nil, true )
					end
				end
			else
				SortPlayer( Player, Client, IsCommander, Pass )
			end
		end

		for Pass = 1, 2 do
			for i = 1, Count do
				AddPlayer( Players[ i ], Pass )
			end
		end

		-- Sanity check the total number of players in case bots bring the total over the max player slot limit.
		self:RemoveBotsIfNeeded( Targets, TeamMembers )

		local function IsValidClient( Client )
			return Shine:IsValidClient( Client )
		end
		local function GetControllingPlayer( Client )
			return Client:GetControllingPlayer()
		end
		local function IsBeingShuffled( Player )
			return PlayersToBeShuffled[ Player ]
		end
		local function IsNotEmptyGroup( Group )
			return #Group.Players > 1
		end

		-- Convert client-based groups into player-based groups for the optimiser to use.
		local PlayerGroups = Shine.Stream.Of( self.FriendGroups ):Map( function( Group )
			return {
				Players = Shine.Stream.Of( Group.Clients )
					:Filter( IsValidClient )
					:Map( GetControllingPlayer )
					:Filter( IsBeingShuffled )
					:AsTable()
			}
		end ):Filter( IsNotEmptyGroup ):AsTable()

		-- Ensure that each group has consistent team preferences.
		self:ConsolidateGroupTeamPreferences( TeamMembers, PlayerGroups, AddTeamPreference )

		TeamMembers.PlayerGroups = PlayerGroups

		self.Logger:IfDebugEnabled( DebugLogTeamMembers, self, Targets, TeamMembers )

		return Targets, TeamMembers
	end
end

function Plugin:ConsolidateGroupTeamPreferences( TeamMembers, PlayerGroups, AddTeamPreference )
	for i = 1, #PlayerGroups do
		local Group = PlayerGroups[ i ]
		local TeamPrefCounts = { 0, 0 }
		for j = 1, #Group.Players do
			local Player = Group.Players[ j ]
			local TeamPreference = TeamMembers.TeamPreferences[ Player ]
			if TeamPreference then
				TeamPrefCounts[ TeamPreference ] = TeamPrefCounts[ TeamPreference ] + 1
			end
		end

		if Max( TeamPrefCounts[ 1 ], TeamPrefCounts[ 2 ] ) ~= 0 then
			-- Players in the group have team preferences, use the most common team or otherwise
			-- remove the preferences to avoid unnecessary additional constraints.
			local GroupPreference = 1
			if TeamPrefCounts[ 1 ] == TeamPrefCounts[ 2 ] then
				GroupPreference = nil
			elseif TeamPrefCounts[ 2 ] > TeamPrefCounts[ 1 ] then
				GroupPreference = 2
			end

			for j = 1, #Group.Players do
				local Player = Group.Players[ j ]
				AddTeamPreference( Player, Player:GetClient(), GroupPreference )
			end
		end
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
	self.ReconnectLogTimeout = SharedTime() + self.Config.ReconnectLogTimeInSeconds
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
	local TeamSkillEnabled = self:IsPerTeamSkillEnabled()
	local CommanderSkillEnabled = self:IsCommanderSkillEnabled()

	local Team1Skills = Shine.Stream( Team1Players ):Map( function( Player )
		return SkillGetter( Player, 1, TeamSkillEnabled, CommanderSkillEnabled ) or 0
	end ):AsTable()

	local Team2Skills = Shine.Stream( Team2Players ):Map( function( Player )
		return SkillGetter( Player, 2, TeamSkillEnabled, CommanderSkillEnabled ) or 0
	end ):AsTable()

	local StdDev1, Average1 = StandardDeviation( Team1Skills )
	local StdDev2, Average2 = StandardDeviation( Team2Skills )

	local function GetCostWithPlayerOnTeam( Skills, TeamNumber, AverageOther, StdDevOther )
		Skills[ #Skills + 1 ] = SkillGetter( Player, TeamNumber, TeamSkillEnabled, CommanderSkillEnabled ) or 0

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

do
	local function GetPlayersOnTeam( Team )
		local Players = {}

		-- Team:GetPlayers() returns the same table every time, which is not helpful...
		Team:ForEachPlayer( function( Player )
			Players[ #Players + 1 ] = Player
		end )

		return Players
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
			local Team1Players = GetPlayersOnTeam( Gamerules.team1 )
			local Team2Players = GetPlayersOnTeam( Gamerules.team2 )

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
end

function Plugin:QueueShuffleOnNextRound( Reason, SkipEnforcement )
	self.ShuffleOnNextRound = true
	self.ShuffleOnNextRoundReason = Reason
	self.ShuffleOnNextRoundSkipEnforcement = SkipEnforcement
end

function Plugin:ResetQueuedNextRoundShuffle()
	self.ShuffleOnNextRound = false
	self.ShuffleOnNextRoundReason = nil
	self.ShuffleOnNextRoundSkipEnforcement = nil
end

function Plugin:CancelQueuedNextRoundShuffleFor( Reason )
	if self.ShuffleOnNextRoundReason ~= Reason then return end

	self:ResetQueuedNextRoundShuffle()
end

function Plugin:CancelEndOfRoundShuffle()
	if not self.EndOfRoundShuffleTimer then return end

	self.EndOfRoundShuffleTimer:Destroy()
	self.EndOfRoundShuffleTimer = nil
end

function Plugin:ApplyAutoShuffle()
	if self.Config.AutoShuffleAtRoundStart then
		-- Reset any vote, as it cannot be used again until the round ends.
		self.Vote:Reset()

		-- If voted to disable auto-shuffle, do nothing.
		if self.SuppressAutoShuffle then return end
	end

	local Reason = self.ShuffleOnNextRoundReason
	local SkipEnforcement = self.ShuffleOnNextRoundSkipEnforcement

	self:ResetQueuedNextRoundShuffle()

	if ( not Reason and GetNumPlayers() < self:GetCurrentVoteConstraints().MinPlayers ) or self.DoneStartShuffle then
		return
	end

	self.DoneStartShuffle = true

	local OldValue = self.Config.IgnoreCommanders

	-- Force ignoring commanders.
	self.Config.IgnoreCommanders = true

	self:SendTranslatedNotify( nil, Reason or "AUTO_SHUFFLE", {
		ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
	} )
	self:ShuffleTeams()

	if not SkipEnforcement then
		self:InitEnforcementPolicy( self:GetVoteActionSettings( self.QueuedStage ) )
		self.QueuedStage = nil
	end

	self.Config.IgnoreCommanders = OldValue
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
	-- Reset the block time when the round stops.
	if NewState == kGameState.NotStarted then
		self.VoteBlockTime = nil
	end

	self:HandleFriendGroupSetGameState( Gamerules, NewState, OldState )

	if NewState ~= kGameState.Countdown then return end

	self:CancelEndOfRoundShuffle()
	self:BroadcastModuleEvent( "GameStarting", Gamerules )
	self.EnforcementPolicy:OnStageChange( self.Stage.InGame )
	self.InGameStateChangeTime = SharedTime() + self.Config.VoteConstraints.InGame.StartOfRoundGraceTimeInSeconds

	-- Block the vote after the set time.
	if self.Config.BlockAfterRoundTimeInMinutes > 0 then
		self.VoteBlockTime = SharedTime() + self.Config.BlockAfterRoundTimeInMinutes * 60
	end

	if not self.Config.AutoShuffleAtRoundStart and not self.ShuffleOnNextRound then return end

	self:ApplyAutoShuffle()
end

function Plugin:ResetGame( Gamerules )
	self:BroadcastModuleEvent( "ResetGame", Gamerules )

	-- Make sure auto-shuffle is applied again the next time the round starts.
	self.DoneStartShuffle = false
end

function Plugin:EndGame( Gamerules, WinningTeam )
	self.LastAttemptedTeamJoins = {}
	self:SendNetworkMessage( nil, "TemporaryTeamPreference", {
		PreferredTeam = 0,
		Silent = true
	}, true )
	self:UpdateAllFriendGroupTeamPreferences()

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
	if self.Config.AutoShuffleAtRoundStart then
		self.SuppressAutoShuffle = false
		self.dt.IsAutoShuffling = true
		self.dt.IsVoteForAutoShuffle = true

		self:DestroyTimer( self.RandomEndTimer )
		self.EnforcementPolicy = NoOpEnforcement()

		return
	end

	if self.ShuffleAtEndOfRound then
		self.ShuffleAtEndOfRound = false

		-- Queue a shuffle for the next round (in case a round starts before the timer expires).
		self:QueueShuffleOnNextRound( "PREVIOUS_VOTE_SHUFFLE" )
		self:CancelEndOfRoundShuffle()

		self.EndOfRoundShuffleTimer = self:SimpleTimer( self.Config.EndOfRoundShuffleDelayInSeconds, function()
			-- If a round hasn't started yet, cancel the queued shuffle.
			self:CancelQueuedNextRoundShuffleFor( "PREVIOUS_VOTE_SHUFFLE" )

			-- Make sure the map hasn't ended, and no round has started yet (if a round starts, it will shuffle
			-- automatically due to the flags set above).
			local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
			local IsEndOfMapVote = Enabled and MapVote:IsEndVote()
			local CurrentStage = self:GetStage( true )
			if IsEndOfMapVote or CurrentStage == self.Stage.InGame then
				self.Logger:Debug(
					"Skipping end of round shuffle as it is not applicable to the current game state (%s - %s)",
					CurrentStage,
					IsEndOfMapVote and "end of map vote in progress" or "no map vote in progress"
				)
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

	-- Make sure the enforcement policy will be active after the configured delay.
	if not self.EnforcementPolicy:IsActive( self, SharedTime() + self.Config.EndOfRoundShuffleDelayInSeconds ) then
		return
	end

	self:QueueShuffleOnNextRound( "PREVIOUS_VOTE_SHUFFLE", true )
	self:CancelEndOfRoundShuffle()

	-- Continue the existing policy (must be time based).
	self.EndOfRoundShuffleTimer = self:SimpleTimer( self.Config.EndOfRoundShuffleDelayInSeconds, function()
		self:CancelQueuedNextRoundShuffleFor( "PREVIOUS_VOTE_SHUFFLE" )

		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
		local IsEndOfMapVote = Enabled and MapVote:IsEndVote()
		local CurrentStage = self:GetStage( true )
		if IsEndOfMapVote or not self.EnforcementPolicy:IsActive( self ) or CurrentStage == self.Stage.InGame then
			self.Logger:Debug(
				"Skipping enforcement shuffle as it is not applicable to the current game state (%s - %s)",
				CurrentStage,
				IsEndOfMapVote and "end of map vote in progress" or "no map vote in progress"
			)
			return
		end

		self:SendTranslatedNotify( nil, "PREVIOUS_VOTE_SHUFFLE", {
			ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
		} )
		self:ShuffleTeams()
	end )
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end

	local Gamestate = Gamerules:GetGameState()

	-- We'll do a mass balance, don't worry about them yet.
	if self.Config.AutoShuffleAtRoundStart and Gamestate < kGameState.PreGame then return end

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

	self:HandleFriendGroupClientDisconnect( Client )

	if not self.ReconnectLogTimeout then return end
	if SharedTime() > self.ReconnectLogTimeout then return end

	self.ReconnectingClients[ Client:GetUserId() ] = true
end

function Plugin:ClientConnect( Client )
	self:UpdateVoteCounters( self.Vote )
	self:HandleFriendGroupClientConnect( Client )

	if not self.ReconnectingClients or not self.ReconnectLogTimeout then return end

	if SharedTime() > self.ReconnectLogTimeout then
		self.ReconnectingClients = nil

		return
	end

	if not self.ReconnectingClients[ Client:GetUserId() ] then return end

	self:Print( "Client %s reconnected after a shuffle vote.", true,
		Shine.GetClientInfo( Client ) )
end

function Plugin:MapChange()
	self:SaveFriendGroups()
end

function Plugin:GetCurrentVoteConstraints()
	return self.Config.VoteConstraints[ self:GetStage() ]
end

function Plugin:GetVotesNeeded()
	local PlayerCount = self:GetPlayerCountForVote()
	return Ceil( PlayerCount * self:GetCurrentVoteConstraints().FractionNeededToPass )
end

function Plugin:GetStartFailureMessage()
	return "ERROR_CANNOT_START", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
end

function Plugin:IsPlayerEligibleForShuffle( AFKKick, Player, IsRookieMode )
	local Client = Player:GetClient()
	if not Shine:IsValidClient( Client ) then return false end

	if Client:GetIsVirtual() then
		return self.Config.ApplyToBots
	end

	if
		( IsRookieMode and not Player:GetIsRookie() ) or
		( AFKKick and self:IsClientAFK( AFKKick, Client ) ) or
		Shine:HasAccess( Client, "sh_randomimmune" )
	then
		return false
	end

	return true
end

function Plugin:HasEligiblePlayersInReadyRoom()
	local Gamerules = GetGamerules()
	if not Gamerules then return false end

	local ReadyRoomTeam = Gamerules:GetTeam( kTeamReadyRoom )
	if not ReadyRoomTeam then return false end

	local IsRookieMode = self:IsRookieModeEnabled( Gamerules )

	local AFKEnabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )
	-- Apply AFK check only if available and configured to do so.
	AFKKick = AFKEnabled and self.Config.RemoveAFKPlayersFromTeams and AFKKick

	local HasEligiblePlayer = false
	local function CheckPlayer( Player )
		if self:IsPlayerEligibleForShuffle( AFKKick, Player, IsRookieMode ) then
			HasEligiblePlayer = true
			return false
		end
	end

	ReadyRoomTeam:ForEachPlayer( CheckPlayer )

	return HasEligiblePlayer
end

function Plugin:EvaluateConstraints( NumPlayers, TeamStats )
	local NumOnTeam1 = #TeamStats[ 1 ].Skills
	local NumOnTeam2 = #TeamStats[ 2 ].Skills
	local NumPlayersOnPlayingTeams = NumOnTeam1 + NumOnTeam2
	local FractionOfPlayersOnTeams = NumPlayersOnPlayingTeams / NumPlayers
	local Constraints = self:GetCurrentVoteConstraints()

	if FractionOfPlayersOnTeams < Constraints.MinPlayerFractionToConstrainSkillDiff then
		-- Not enough players on playing teams to apply constraints.
		self.Logger:Debug( "Permitting vote as only %s of all players are on teams.", FractionOfPlayersOnTeams )
		return true
	end

	local PlayerSizeDiff = Abs( NumOnTeam1 - NumOnTeam2 )
	if PlayerSizeDiff == 1 and self:HasEligiblePlayersInReadyRoom() then
		-- Teams are off by one, and there's at least 1 player that would be moved onto a team if a shuffle happens.
		self.Logger:Debug( "Permitting vote as there is a player in the ready room that can make team counts even." )
		return true
	end

	if PlayerSizeDiff > 1 then
		-- Imbalanced number of players on teams, permit a shuffle.
		self.Logger:Debug( "Permitting vote as team counts are uneven: %s vs. %s", NumOnTeam1, NumOnTeam2 )
		return true
	end

	local AverageDiff = Abs( TeamStats[ 1 ].Average - TeamStats[ 2 ].Average )
	if AverageDiff >= Constraints.MinAverageDiffToAllowShuffle then
		-- Teams are far enough apart in average skill to allow the vote.
		self.Logger:Debug( "Permitting vote as average difference is: %s", AverageDiff )
		return true
	end

	local StdDiff = Abs( TeamStats[ 1 ].StandardDeviation - TeamStats[ 2 ].StandardDeviation )
	local MinStdDiff = Constraints.MinStandardDeviationDiffToAllowShuffle
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
	local Allow, Error, TranslationKey, Args = Shine.Hook.Call( "OnVoteStart", "random", self )
	if Allow == false then
		return false, TranslationKey, Args
	end
	return true
end

function Plugin:CanStartVote()
	if self:GetStage() == self.Stage.InGame and self.Config.AutoShuffleAtRoundStart then
		-- Disabling/enabling auto shuffle should only be possible before a round starts.
		return false, self:GetStartFailureMessage()
	end

	local Time = SharedTime()
	if self.VoteBlockTime and self.VoteBlockTime < Time then
		return false, "ERROR_ROUND_TOO_FAR"
	end

	do
		local Allowed, Err, Args = self:IsVoteAllowed()
		if not Allowed then
			return Allowed, Err, Args
		end
	end

	if self.NextVote > Time then
		local TimeTillNextVote = Ceil( self.NextVote - Time )
		return false, "ERROR_MUST_WAIT", {
			ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ],
			SecondsToWait = TimeTillNextVote
		}
	end

	if self.ShuffleOnNextRound or self.ShuffleAtEndOfRound then
		return false, "ERROR_ALREADY_ENABLED", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
	end

	if self:GetPlayerCountForVote() < self:GetCurrentVoteConstraints().MinPlayers then
		return false, "ERROR_NOT_ENOUGH_PLAYERS"
	end

	if self.Config.BalanceMode == self.ShuffleMode.HIVE
	and not self:EvaluateConstraints( GetNumPlayers() - GetNumSpectators(), self:GetTeamStats() ) then
		return false, "ERROR_CONSTRAINTS"
	end

	return true
end

--[[
	Adds a player's vote to the counter.
]]
function Plugin:AddVote( Client )
	do
		local Success, Err, Args = self:CanClientVote( Client )
		if not Success then
			return false, Err, Args
		end

		Success, Err, Args = self:CanStartVote()
		if not Success then
			return false, Err, Args
		end
	end

	if not self.Vote:AddVote( Client ) then
		return false, "ERROR_ALREADY_VOTED", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
	end

	return true
end

Plugin.Stage = table.AsEnum{
	"PreGame", "InGame"
}

function Plugin:IsRoundActive( GameState, IgnoreGraceTime )
	return GameState >= kGameState.Countdown and GameState <= kGameState.Started
		and ( IgnoreGraceTime or not self.InGameStateChangeTime or SharedTime() >= self.InGameStateChangeTime )
end

function Plugin:GetStage( IgnoreGraceTime )
	local Gamerules = GetGamerules()
	if not Gamerules then return self.Stage.PreGame end

	local GameState = Gamerules:GetGameState()
	return self:IsRoundActive( GameState, IgnoreGraceTime ) and self.Stage.InGame or self.Stage.PreGame
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
			ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
		} )
		self:ResetQueuedNextRoundShuffle()
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
			ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
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

do
	local function PolicyToString( Policy )
		return StringFormat( "<%s [%s, %s]>", Policy.Type, Policy.MinPlayers, Policy.MaxPlayers )
	end

	function Plugin:BuildEnforcementPolicy( Settings )
		if #Settings.EnforcementPolicy == 0 then
			self.Logger:Debug( "No enforcement policies configured, disabling enforcement." )
			-- No policies configured, so nothing to enforce.
			return self.EnforcementPolicies[ self.EnforcementDurationType.NONE ]( self, Settings )
		end

		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug(
				"Applying enforcement policies [ %s ] with duration type %s",
				Shine.Stream.Of( Settings.EnforcementPolicy ):Map( PolicyToString ):Concat( ", " ),
				Settings.EnforcementDurationType
			)
		end

		return self.EnforcementPolicies[ Settings.EnforcementDurationType ]( self, Settings )
	end
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

	if self.Config.AutoShuffleAtRoundStart then
		self.SuppressAutoShuffle = not self.SuppressAutoShuffle
		self.dt.IsAutoShuffling = not self.SuppressAutoShuffle

		local Key = self.SuppressAutoShuffle and "AUTO_SHUFFLE_DISABLED" or "AUTO_SHUFFLE_ENABLED"
		self:SendTranslatedNotify( nil, Key, {
			ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
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
					if self.Config.AutoShuffleAtRoundStart then
						Key = self.SuppressAutoShuffle and "PLAYER_VOTED_ENABLE_AUTO"
							or "PLAYER_VOTED_DISABLE_AUTO"
					end

					self:SendTranslatedNotify( nil, Key, {
						ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ],
						VotesNeeded = VotesNeeded,
						PlayerName = PlayerName
					} )
				else
					local Key = "PLAYER_VOTED_PRIVATE"
					if self.Config.AutoShuffleAtRoundStart then
						Key = self.SuppressAutoShuffle and "PLAYER_VOTED_ENABLE_AUTO_PRIVATE"
							or "PLAYER_VOTED_DISABLE_AUTO_PRIVATE"
					end

					self:SendTranslatedNotify( Client, Key, {
						ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ],
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
				ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
			} )
		else
			self.Vote:Reset()

			if self.Config.AutoShuffleAtRoundStart then
				self.SuppressAutoShuffle = true
				self.dt.IsAutoShuffling = false
			end

			self:ResetQueuedNextRoundShuffle()
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
			local Stats = TeamStats[ i ]
			local Skills = Stats.Skills

			Message[ #Message + 1 ] = "======================"
			Message[ #Message + 1 ] = StringFormat(
				"%s (%d player%s)",
				Shine:GetTeamName( i, true ),
				#Skills,
				#Skills == 1 and "" or "s"
			)
			Message[ #Message + 1 ] = "======================"

			for j = 1, #Skills do
				Message[ #Message + 1 ] = tostring( Skills[ j ] )
			end

			Message[ #Message + 1 ] = StringFormat( "Average: %.1f. Standard Deviation: %.1f.",
				Stats.Average, Stats.StandardDeviation )
		end

		local BalanceModeConfig = self:GetBalanceModeConfig()

		Message[ #Message + 1 ] = StringFormat(
			"Team skills are %s. Commander skills are %s. Alien commander skill blending is %s.",
			self:IsPerTeamSkillEnabled() and "enabled" or "disabled",
			self:IsCommanderSkillEnabled() and "enabled" or "disabled",
			BalanceModeConfig and BalanceModeConfig.BlendAlienCommanderAndFieldSkills and "enabled" or "disabled"
		)
		Message[ #Message + 1 ] = StringFormat( "Team preference cost weighting: %s. History rounds: %d.",
			self.Config.TeamPreferences.CostWeighting, self.Config.TeamPreferences.MaxHistoryRounds )
		Message[ #Message + 1 ] = StringFormat( "Play with friends cost weighting: %s. Max group size: %d.",
			self.Config.TeamPreferences.PlayWithFriendsWeighting, self.Config.TeamPreferences.MaxFriendGroupSize )

		local CurrentHappinessWeight = self:GetHistoricHappinessWeightForClient( Client )
		Message[ #Message + 1 ] = StringFormat(
			"Your current team preference weighting multiplier: %s.",
			CurrentHappinessWeight
		)

		if self.LastShuffleTime then
			Message[ #Message + 1 ] = StringFormat(
				"Last shuffle was %s ago. %d/%d player(s) match their team from the last shuffle.",
				string.TimeToString( SharedTime() - self.LastShuffleTime ),
				TeamStats.NumMatchingTeams or 0,
				TeamStats.TotalPlayers or 0
			)

			Message[ #Message + 1 ] = StringFormat(
				"%d/%d player(s) were placed on their preferred team.",
				TeamStats.NumPreferencesHeld or 0,
				TeamStats.NumPreferencesTotal or 0
			)

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

Shine.LoadPluginFile( PluginName, "local_stats.lua", Plugin )
Shine.LoadPluginModule( "vote.lua", Plugin )
Shine.LoadPluginModule( "logger.lua", Plugin )
