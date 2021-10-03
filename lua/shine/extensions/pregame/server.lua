--[[
	Shine pregame countdown plugin.
]]

local Shine = Shine
local IsType = Shine.IsType

local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local Max = math.max
local SharedTime = Shared.GetTime
local StringFormat = string.format

local Plugin = ...
Plugin.Version = "1.9"

Plugin.HasConfig = true
Plugin.ConfigName = "PreGame.json"
Plugin.PrintName = "Pre Game"
Plugin.NotifyPrefixColour = {
	100, 100, 255
}

Plugin.Modes = table.AsEnum( {
	"TIME",
	"ONE_COMMANDER_COUNTDOWN",
	"MAX_WAIT_TIME",
	"MIN_PLAYER_COUNT"
} )

Plugin.DefaultConfig = {
	-- How long the pre-game should last (for TIME, ONE_COMMANDER_COUNTDOWN and MAX_WAIT_TIME).
	PreGameTimeInSeconds = 45,
	-- How long to countdown before starting the game once commander constraints are satisfied.
	CountdownTimeInSeconds = 15,
	-- How long to wait after the map has loaded before starting to check commanders/constraints.
	StartDelayInSeconds = 30,
	-- Whether to show a countdown when the game is about to start.
	ShowCountdown = true,
	-- The mode to use to control game start behaviour.
	Mode = Plugin.Modes.ONE_COMMANDER_COUNTDOWN,
	-- The minimum number of players required to start the game (when using MIN_PLAYER_COUNT).
	MinPlayers = 0,
	-- Whether to abort the game start if a commander drops out of the chair.
	AbortIfNoCom = false,
	-- The team numbers that should cause the game start to abort if they are empty (only 1 and 2 are supported).
	-- This is mainly to allow for mods that use only one team to start a round to work with the plugin.
	AbortIfTeamsEmpty = { 1, 2 },
	-- Whether to allow players to attack during the pre-game time.
	AllowAttackPreGame = true,
	-- Whether to automatically add commander bots for any team without a commander at game start.
	AutoAddCommanderBots = true
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.FiveSecTimer = "PreGameFiveSeconds"
Plugin.CountdownTimer = "PreGameCountdown"

Plugin.StartNagInterval = 30

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.7",
		Apply = Shine.Migrator()
			:RenameField( "CountdownTime", "CountdownTimeInSeconds" )
			:RenameField( "PreGameTime", "PreGameTimeInSeconds" )
			:RenameField( "StartDelay", "StartDelayInSeconds" )
			:ApplyAction( function( Config )
				if not IsType( Config.RequireComs, "number" ) then return end

				Config.Mode = Config.RequireComs + 1
				Config.RequireComs = nil
			end )
			:UseEnum( "Mode", Plugin.Modes )
	},
	{
		VersionTo = "1.8",
		Apply = Shine.Migrator()
			:AddField( "AutoAddCommanderBots", true )
			:AddField( "LogLevel", "INFO" )
	},
	{
		VersionTo = "1.9",
		Apply = Shine.Migrator()
			:AddField( "AbortIfTeamsEmpty", { 1, 2 } )
	}
}

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "CountdownTimeInSeconds", Validator.Min( 0 ) )
	Validator:AddFieldRule( "Mode", Validator.InEnum( Plugin.Modes, Plugin.Modes.ONE_COMMANDER_COUNTDOWN ) )
	Validator:AddFieldRule( "MinPlayers", Validator.Min( 0 ) )
	Validator:AddFieldRule( "MinPlayers", Validator.Integer() )
	Validator:AddFieldRule( "PreGameTimeInSeconds", Validator.Min( 0 ) )
	Validator:AddFieldRule( "StartDelayInSeconds", Validator.Min( 0 ) )
	Validator:AddFieldRule(
		"AbortIfTeamsEmpty",
		Validator.AllValuesSatisfy( Validator.IsType( "number" ), Validator.Integer(), Validator.Clamp( 1, 2 ) )
	)

	Plugin.ConfigValidator = Validator
end

function Plugin:OnFirstThink()
	Shine.Hook.SetupClassHook( "Player", "GetCanAttack", "CheckPlayerCanAttack", "ActivePre" )
end

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.CountStart = nil
	self.CountEnd = nil
	self.GameStarting = false
	self.StartedGame = false

	self.TeamsToEmptyCheck = {}
	for i = 1, #self.Config.AbortIfTeamsEmpty do
		self.TeamsToEmptyCheck[ self.Config.AbortIfTeamsEmpty[ i ] ] = true
	end

	self.Enabled = true

	return true
end

function Plugin:OnMapVoteStarted( MapVotePlugin, IsNextMapVote, EndTime )
	if IsNextMapVote then return end

	local Gamerules = GetGamerules()
	if not Gamerules then return end

	if Gamerules:GetGameState() < kGameState.Countdown and self:IsGameStarting() then
		self:AbortGameStart( Gamerules, "ROUND_START_ABORTED_MAP_VOTE_STARTED" )
		self:ResetStartEndTime()
	end
end

function Plugin:AddCommanderBotIfNeeded( Gamerules, BotController, TeamNumber )
	if not BotController:GetTeamHasCommander( TeamNumber ) then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "Adding commander bot to team %s...", TeamNumber )
		end
		OnConsoleAddBots( nil, 1, TeamNumber, "com" )
		Gamerules.removeCommanderBots = true
	end
end

function Plugin:AddCommanderBots( Gamerules )
	local BotController = Gamerules.botTeamController
	if not BotController or not BotController.GetTeamHasCommander then
		self.Logger:Warn( "Unable to add commander bots as the gamerules has no valid BotTeamController instance." )
		return
	end

	if not OnConsoleAddBots then
		self.Logger:Warn( "Unable to add commander bots, OnConsoleAddBots does not exist." )
		return
	end

	self:AddCommanderBotIfNeeded( Gamerules, BotController, kTeam1Index )
	self:AddCommanderBotIfNeeded( Gamerules, BotController, kTeam2Index )
end

function Plugin:StartCountdown()
	local Gamerules = GetGamerules()
	if not Gamerules then return end

	if self.Config.AutoAddCommanderBots then
		self:AddCommanderBots( Gamerules )
	end

	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength
	Gamerules.lastCountdownPlayed = nil

	local Players, Count = Shine.GetAllPlayers()

	for i = 1, Count do
		local Player = Players[ i ]

		if Player.ResetScores then
			Player:ResetScores()
		end
	end

	self.StartedGame = false
	self.GameStarting = false
end

function Plugin:ClientConfirmConnect( Client )
	local StartDelay = self.Config.StartDelayInSeconds

	if StartDelay > 0 and SharedTime() < StartDelay then
		self:SendNetworkMessage( Client, "StartDelay",
			{ StartTime = Floor( StartDelay ) }, true )
	end

	if not self.CountStart then return end
	if not self.Config.ShowCountdown then return end

	local TimeLeft = Ceil( self.CountEnd - SharedTime() )

	if TimeLeft <= 0 or TimeLeft > 5 then return end

	self:ShowCountdown( TimeLeft, Client )
end

function Plugin:CheckPlayerCanAttack()
	if self.Config.AllowAttackPreGame then return end

	local Gamerules = GetGamerules()
	local GameState = Gamerules:GetGameState()

	if GameState == kGameState.PreGame or GameState == kGameState.NotStarted then
		return false
	end
end

function Plugin:SetGameState( Gamerules, State, OldState )
	if State < kGameState.Countdown then return end

	if self.CountStart then
		self.CountStart = nil
		self.CountEnd = nil
		self.SentCountdown = nil
	end

	self.StartedGame = false
	self.GameStarting = false
	self:DestroyTimers()
	Shine.ScreenText.End( self.ScreenTextID )

	-- Removes start delay text if game start was forced.
	if self.Config.StartDelayInSeconds > 0 then
		self:SendNetworkMessage( nil, "StartDelay", { StartTime = 0 }, true )
	end
end

function Plugin:DestroyTimers()
	self:DestroyTimer( self.FiveSecTimer )
	self:DestroyTimer( self.CountdownTimer )
end

function Plugin:ResetStartEndTime()
	self.CountStart = nil
	self.CountEnd = nil
end

function Plugin:AbortGameStart( Gamerules, Message, Args )
	self:DestroyTimers()
	self.GameStarting = false
	self.SentCountdown = nil

	if self.Config.Mode == self.Modes.MAX_WAIT_TIME then
		self.StartedGame = false
	else
		self:ResetStartEndTime()
	end

	Gamerules:SetGameState( kGameState.NotStarted )

	if Message then
		if Args then
			self:SendTranslatedNotify( nil, Message, Args )
		else
			self:NotifyTranslated( nil, Message )
		end
	end

	Shine.ScreenText.End( self.ScreenTextID )
end

function Plugin:ShowGameStart( TimeTillStart )
	if self.Config.ShowCountdown then
		self:SendTranslatedNotify( nil, "GameStartsSoon", {
			Duration = TimeTillStart
		} )
	end
end

function Plugin:ShowCountdown( Duration, Client )
	self:SendTranslatedNotify( Client, "GameStarting", {
		Duration = Duration or 5
	} )
end

function Plugin:NagForTeam( WaitingForTeam )
	self:SendTranslatedNotify( nil, "WaitingForTeam", {
		Team = WaitingForTeam
	} )
end

function Plugin:NagForBoth()
	self:SendTranslatedNotify( nil, "WaitingForBoth" )
end

function Plugin:CheckEmptyTeams( Team1Count, Team2Count )
	if self.TeamsToEmptyCheck[ 1 ] and Team1Count == 0 then
		return 1
	end

	if self.TeamsToEmptyCheck[ 2 ] and Team2Count == 0 then
		return 2
	end

	return nil
end

function Plugin:AbortDueToEmptyTeam( Gamerules, EmptyTeam )
	self.Logger:Debug( "Aborting game start as team %s is empty.", EmptyTeam )
	self:AbortGameStart( Gamerules, "EmptyTeamAbort", {
		Team = EmptyTeam
	} )
end

function Plugin:QueueGameStart( Gamerules )
	self.GameStarting = true

	Gamerules:SetGameState( kGameState.PreGame )

	local CountdownTime = self.Config.CountdownTimeInSeconds

	if self.Config.ShowCountdown then
		self:ShowGameStart( CountdownTime )
	end

	self:CreateTimer( self.FiveSecTimer, CountdownTime - 5, 1, function()
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2
		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		if self.Config.AbortIfNoCom then
			if not Team1Com or not Team2Com then
				return
			end
		end

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		local EmptyTeam = self:CheckEmptyTeams( Team1Count, Team2Count )
		if EmptyTeam then
			return
		end

		self:ShowCountdown()
	end )

	self:CreateTimer( self.CountdownTimer, CountdownTime, 1, function()
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2
		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		if self.Config.AbortIfNoCom then
			if not Team1Com or not Team2Com then
				self:AbortGameStart( Gamerules, "ABORT_COMMANDER_DROP" )
				return
			end
		end

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		local EmptyTeam = self:CheckEmptyTeams( Team1Count, Team2Count )
		if EmptyTeam then
			self:AbortDueToEmptyTeam( Gamerules, EmptyTeam )
			return
		end

		self:StartCountdown()
	end )
end

function Plugin:CheckTeamCounts( Gamerules, Team1Com, Team2Com, Team1Count, Team2Count )
	if self.Config.AbortIfNoCom and ( not Team1Com or not Team2Com ) then
		self:AbortGameStart( Gamerules, "ABORT_COMMANDER_DROP" )
		return
	end

	local EmptyTeam = self:CheckEmptyTeams( Team1Count, Team2Count )
	if EmptyTeam then
		self:AbortDueToEmptyTeam( Gamerules, EmptyTeam )
		return
	end
end

Plugin.GameStartingCheck = {
	[ Plugin.Modes.TIME ] = function( self )
		return self.CountStart ~= nil
	end,
	[ Plugin.Modes.ONE_COMMANDER_COUNTDOWN ] = function( self )
		return self.GameStarting or self.CountStart ~= nil
	end,
	[ Plugin.Modes.MAX_WAIT_TIME ] = function( self )
		return self.GameStarting or ( self.CountEnd and self.CountEnd - SharedTime() <= 0 )
	end,
	[ Plugin.Modes.MIN_PLAYER_COUNT ] = function( self )
		return self.GameStarting
	end
}

function Plugin:IsGameStarting()
	return self.GameStartingCheck[ self.Config.Mode ]( self )
end

Plugin.UpdateFuncs = {
	-- Legacy functionality, fixed time for pregame then start.
	[ Plugin.Modes.TIME ] = function( self, Gamerules )
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		local Time = SharedTime()

		local EmptyTeam = self:CheckEmptyTeams( Team1Count, Team2Count )
		if EmptyTeam then
			if self.CountStart then
				self:AbortDueToEmptyTeam( Gamerules, EmptyTeam )
			end

			return
		end

		if not self.CountStart then
			local Duration = self.Config.PreGameTimeInSeconds

			self.CountStart = Time
			self.CountEnd = Time + Duration
			self.GameStarting = true

			Gamerules:SetGameState( kGameState.PreGame )

			self:ShowGameStart( Duration )

			return
		end

		local TimeLeft = Ceil( self.CountEnd - Time )

		if TimeLeft == 5 then
			if self.Config.ShowCountdown and not self.SentCountdown then
				self:ShowCountdown()
				self.SentCountdown = true
			end
		end

		if self.CountEnd <= Time then
			self.CountStart = nil
			self.CountEnd = nil
			self.SentCountdown = nil
			self:StartCountdown()

			return
		end
	end,

	-- Once one team has a commander, start a long countdown.
	[ Plugin.Modes.ONE_COMMANDER_COUNTDOWN ] = function( self, Gamerules )
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		if self.GameStarting then
			self:CheckTeamCounts( Gamerules, Team1Com, Team2Com, Team1Count, Team2Count )
			return
		end

		local Time = SharedTime()

		-- Both teams have a commander, begin countdown,
		-- but only if the 1 commander countdown isn't past the 2
		-- commander countdown time length left.
		if Team1Com and Team2Com and not self.GameStarting
		and not ( self.CountEnd and self.CountEnd - Time <= self.Config.CountdownTimeInSeconds ) then
			self:QueueGameStart( Gamerules )
			return
		end

		-- A team no longer has players, abort the timer.
		local EmptyTeam = self:CheckEmptyTeams( Team1Count, Team2Count )
		if EmptyTeam then
			if self.CountStart then
				self:AbortDueToEmptyTeam( Gamerules, EmptyTeam )
			end

			return
		end

		if Team1Com or Team2Com then
			if not self.CountStart then
				local Duration = self.Config.PreGameTimeInSeconds

				self.CountStart = Time
				self.CountEnd = Time + Duration

				if self.Config.ShowCountdown then
					self:SendTranslatedNotify( nil, "TeamHasCommander", {
						Team = Team1Com and 1 or 2,
						TimeLeft = Duration
					} )
				end
			end
		else
			if self.Config.AbortIfNoCom and self.CountStart then
				self:AbortGameStart( Gamerules, "ABORT_COMMANDER_DROP" )
			end

			if not self.CountStart and self:CanRunAction( "StartNag", Time, self.StartNagInterval ) then
				self:NagForBoth()
			end
		end

		if not self.CountEnd then return end

		local TimeLeft = Ceil( self.CountEnd - Time )
		if TimeLeft == 5 then
			if self.Config.ShowCountdown and not self.SentCountdown then
				self:ShowCountdown()

				Gamerules:SetGameState( kGameState.PreGame )

				self.SentCountdown = true
			end
		end

		if TimeLeft > 5 and ( Team1Com or Team2Com )
		and self:CanRunAction( "StartNag", Time, self.StartNagInterval ) then
			local WaitingForTeam = Team1Com and 2 or 1
			self:NagForTeam( WaitingForTeam )
		end

		if self.CountEnd <= Time then
			self.CountStart = nil
			self.CountEnd = nil
			self.SentCountdown = nil
			self:StartCountdown()

			return
		end
	end,

	-- After the set time, if one team has a commander, start the game.
	[ Plugin.Modes.MAX_WAIT_TIME ] = function( self, Gamerules )
		local Time = SharedTime()

		if not self.CountStart then
			local Duration = self.Config.PreGameTimeInSeconds

			self.CountStart = Time
			self.CountEnd = Time + Duration

			return
		end

		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		if self.GameStarting then
			self:CheckTeamCounts( Gamerules, Team1Com, Team2Com, Team1Count, Team2Count )
			return
		end

		-- Both teams have a commander, begin countdown.
		if Team1Com and Team2Com and not self.StartedGame then
			self:QueueGameStart( Gamerules )

			return
		end

		local TimeLeft = Ceil( self.CountEnd - Time )

		-- Time's up!
		if TimeLeft <= 0 and ( Team1Com or Team2Com ) then
			local Team1Count = Team1:GetNumPlayers()
			local Team2Count = Team2:GetNumPlayers()

			if Team1Count == 0 or Team2Count == 0 then return end
			if self.StartedGame then return end

			self:SendTranslatedNotify( nil, "EXCEEDED_TIME", {
				Duration = self.Config.PreGameTimeInSeconds
			} )

			self.StartedGame = true

			Gamerules:SetGameState( kGameState.PreGame )

			self:CreateTimer( self.CountdownTimer, 5, 1, function()
				local Team1Com = Team1:GetCommander()
				local Team2Com = Team2:GetCommander()

				if self.Config.AbortIfNoCom then
					if not Team1Com and not Team2Com then
						self:AbortGameStart( Gamerules, "ABORT_COMMANDER_DROP" )
						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				local EmptyTeam = self:CheckEmptyTeams( Team1Count, Team2Count )
				if EmptyTeam then
					self:AbortDueToEmptyTeam( Gamerules, EmptyTeam )
					return
				end

				self:StartCountdown()
			end )

			return
		end

		if not self:CanRunAction( "StartNag", Time, self.StartNagInterval ) then return end

		if Team1Com or Team2Com then
			local WaitingForTeam = Team1Com and 2 or 1
			self:NagForTeam( WaitingForTeam )
		else
			self:NagForBoth()
		end
	end,

	-- Do not allow the game to start until the minimum player count is reached, and there are two commanders.
	[ Plugin.Modes.MIN_PLAYER_COUNT ] = function( self, Gamerules )
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		local Team1Count, Team1Rookies, Team1Bots = Team1:GetNumPlayers()
		local Team2Count, Team2Rookies, Team2Bots = Team2:GetNumPlayers()

		if self.GameStarting then
			self:CheckTeamCounts( Gamerules, Team1Com, Team2Com, Team1Count, Team2Count )
			return
		end

		local PlayerCount = Team1Count + Team2Count - Team1Bots - Team2Bots
		if PlayerCount < self.Config.MinPlayers then
			if self:CanRunAction( "StartNag", SharedTime(), self.StartNagInterval ) then
				self:SendTranslatedNotify( nil, "WaitingForMinPlayers", {
					MinPlayers = self.Config.MinPlayers
				} )
			end

			return
		end

		if Team1Com and Team2Com then
			self:QueueGameStart( Gamerules )
			return
		end

		if not self:CanRunAction( "StartNag", SharedTime(), self.StartNagInterval ) then return end

		if Team1Com or Team2Com then
			local WaitingForTeam = Team1Com and 2 or 1
			self:NagForTeam( WaitingForTeam )
		else
			self:NagForBoth()
		end
	end
}

function Plugin:UpdatePregame( Gamerules )
	if Gamerules:GetGameState() == kGameState.PreGame then
		return false
	end
end

function Plugin:GetNumPlayersFromGamerules( Gamerules )
	local Team1Players, _, Team1Bots = Gamerules.team1:GetNumPlayers()
	local Team2Players, _, Team2Bots = Gamerules.team2:GetNumPlayers()

	return Team1Players + Team2Players - Team1Bots - Team2Bots
end

function Plugin:UpdateWarmUp( Gamerules )
	local State = Gamerules:GetGameState()
	if State ~= kGameState.WarmUp then return end

	local NumPlayers = self:GetNumPlayersFromGamerules( Gamerules )
	if NumPlayers >= Gamerules:GetWarmUpPlayerLimit() then
		-- Restore old behaviour, go to NotStarted when players exceed warm up total.
		Gamerules:SetGameState( kGameState.NotStarted )
		return false
	end
end

function Plugin:CheckGameStart( Gamerules )
	local State = Gamerules:GetGameState()
	if State > kGameState.PreGame then return end

	-- Do not allow starting too soon.
	local StartDelay = self.Config.StartDelayInSeconds
	if StartDelay > 0 and SharedTime() < StartDelay then
		return false
	end

	self.UpdateFuncs[ self.Config.Mode ]( self, Gamerules )

	return false
end

Shine.LoadPluginModule( "logger.lua", Plugin )
