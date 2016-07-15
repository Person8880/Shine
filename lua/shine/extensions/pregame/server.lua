--[[
	Shine pregame countdown plugin.
]]

local Shine = Shine

local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local SharedTime = Shared.GetTime
local StringFormat = string.format

local Plugin = Plugin
Plugin.Version = "1.6"

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
}, function( Index ) return Index end )

Plugin.DefaultConfig = {
	PreGameTime = 45,
	CountdownTime = 15,
	StartDelay = 0,
	ShowCountdown = true,
	Mode = Plugin.Modes.ONE_COMMANDER_COUNTDOWN,
	MinPlayers = 0,
	AbortIfNoCom = false,
	AllowAttackPreGame = true
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.FiveSecTimer = "PreGameFiveSeconds"
Plugin.CountdownTimer = "PreGameCountdown"

Plugin.StartNagInterval = 30

function Plugin:OnFirstThink()
	Shine.Hook.SetupClassHook( "Player", "GetCanAttack",
		"CheckPlayerCanAttack", "ActivePre" )
end

function Plugin:PreValidateConfig( Config )
	if not Config.RequireComs then return end

	Config.Mode = Config.RequireComs + 1
	Config.RequireComs = nil

	return true
end

function Plugin:Initialise()
	local Gamemode = Shine.GetGamemode()

	if Gamemode ~= "ns2" and Gamemode ~= "mvm" then
		return false, StringFormat( "The pregame plugin does not work with %s.", Gamemode )
	end

	self.Config.Mode = Clamp( Floor( self.Config.Mode ), 1, #self.Modes )

	self.CountStart = nil
	self.CountEnd = nil
	self.GameStarting = false
	self.StartedGame = false

	self.Enabled = true

	return true
end

function Plugin:StartCountdown()
	local Gamerules = GetGamerules()

	if not Gamerules then return end

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
	local StartDelay = self.Config.StartDelay

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
	if State <= kGameState.PreGame then return end

	if self.CountStart then
		self.CountStart = nil
		self.CountEnd = nil
		self.SentCountdown = nil
	end

	self.StartedGame = false
	self.GameStarting = false

	--Removes start delay text if game start was forced.
	if self.Config.StartDelay > 0 then
		self:SendNetworkMessage( nil, "StartDelay", { StartTime = 0 }, true )
	end
end

function Plugin:DestroyTimers()
	self:DestroyTimer( self.FiveSecTimer )
	self:DestroyTimer( self.CountdownTimer )
end

function Plugin:AbortGameStart( Gamerules, Message, Args )
	Gamerules:SetGameState( kGameState.NotStarted )

	if Args then
		self:SendTranslatedNotify( nil, Message, Args )
	else
		self:NotifyTranslated( nil, Message )
	end

	Shine.ScreenText.End( 2 )
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

function Plugin:QueueGameStart( Gamerules )
	self.GameStarting = true

	Gamerules:SetGameState( kGameState.PreGame )

	local CountdownTime = self.Config.CountdownTime

	if self.Config.ShowCountdown then
		self:ShowGameStart( CountdownTime )
	end

	self:CreateTimer( self.FiveSecTimer, CountdownTime - 5, 1, function()
		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		if self.Config.AbortIfNoCom then
			if not Team1Com or not Team2Com then
				return
			end
		end

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		if Team1Count == 0 or Team2Count == 0 then
			return
		end

		self:ShowCountdown()
	end )

	self:CreateTimer( self.CountdownTimer, CountdownTime, 1, function()
		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		if self.Config.AbortIfNoCom then
			if not Team1Com or not Team2Com then
				self:AbortGameStart( Gamerules, "ABORT_COMMANDER_DROP" )
				self.SentCountdown = nil
				self.GameStarting = false

				return
			end
		end

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		if Team1Count == 0 or Team2Count == 0 then
			self:AbortGameStart( Gamerules, "EmptyTeamAbort", {
				Team = Team1Count == 0 and 1 or 2
			} )
			self.SentCountdown = nil
			self.GameStarting = false

			return
		end

		self:StartCountdown()
	end )
end

function Plugin:CheckTeamCounts( Gamerules, Team1Com, Team2Com, Team1Count, Team2Count )
	if self.Config.AbortIfNoCom and ( not Team1Com or not Team2Com ) then
		self:DestroyTimers()
		self:AbortGameStart( Gamerules, "ABORT_COMMANDER_DROP" )
		self.GameStarting = false
		self.SentCountdown = nil

		return
	end

	if Team1Count == 0 or Team2Count == 0 then
		self:DestroyTimers()

		self:AbortGameStart( Gamerules, "EmptyTeamAbort", {
			Team = Team1Count == 0 and 1 or 2
		} )

		self.GameStarting = false
		self.SentCountdown = nil

		if self.CountStart then
			self.CountStart = nil
			self.CountEnd = nil
		end

		return
	end
end

Plugin.UpdateFuncs = {
	--Legacy functionality, fixed time for pregame then start.
	function( self, Gamerules )
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		local Time = SharedTime()

		if Team1Count == 0 or Team2Count == 0 then
			if self.CountStart then
				self.CountStart = nil
				self.CountEnd = nil
				self.SentCountdown = nil

				self:AbortGameStart( Gamerules, "EmptyTeamAbort", {
					Team = Team1Count == 0 and 1 or 2
				} )
			end

			return
		end

		if not self.CountStart then
			local Duration = self.Config.PreGameTime

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

	--Once one team has a commander, start a long countdown.
	function( self, Gamerules )
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		local Time = SharedTime()

		if self.GameStarting then
			self:CheckTeamCounts( Gamerules, Team1Com, Team2Com, Team1Count, Team2Count )
			return
		end

		--Both teams have a commander, begin countdown,
		--but only if the 1 commander countdown isn't past the 2
		--commander countdown time length left.
		if Team1Com and Team2Com and not self.GameStarting
		and not ( self.CountEnd and self.CountEnd - Time <= self.Config.CountdownTime ) then
			self:QueueGameStart( Gamerules )
			return
		end

		--A team no longer has players, abort the timer.
		if Team1Count == 0 or Team2Count == 0 then
			if self.CountStart then
				self.CountStart = nil
				self.CountEnd = nil
				self.SentCountdown = nil

				self:AbortGameStart( Gamerules, "EmptyTeamAbort", {
					Team = Team1Count == 0 and 1 or 2
				} )
			end

			return
		end

		if Team1Com or Team2Com then
			if not self.CountStart then
				local Duration = self.Config.PreGameTime

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
				self.CountStart = nil
				self.CountEnd = nil
				self.SentCountdown = nil

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

	--After the set time, if one team has a commander, start the game.
	function( self, Gamerules )
		local Time = SharedTime()

		if not self.CountStart then
			local Duration = self.Config.PreGameTime

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

		--Both teams have a commander, begin countdown.
		if Team1Com and Team2Com and not self.StartedGame then
			self:QueueGameStart( Gamerules )

			return
		end

		local TimeLeft = Ceil( self.CountEnd - Time )

		--Time's up!
		if TimeLeft <= 0 and ( Team1Com or Team2Com ) then
			local Team1Count = Team1:GetNumPlayers()
			local Team2Count = Team2:GetNumPlayers()

			if Team1Count == 0 or Team2Count == 0 then return end
			if self.StartedGame then return end

			self:SendTranslatedNotify( nil, "EXCEEDED_TIME", {
				Duration = self.Config.PreGameTime
			} )

			self.StartedGame = true

			Gamerules:SetGameState( kGameState.PreGame )

			self:SimpleTimer( 5, function()
				local Team1Com = Team1:GetCommander()
				local Team2Com = Team2:GetCommander()

				if self.Config.AbortIfNoCom then
					if not Team1Com and not Team2Com then
						self:AbortGameStart( Gamerules, "ABORT_COMMANDER_DROP" )

						self.StartedGame = false

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then
					self:AbortGameStart( Gamerules, "EmptyTeamAbort", {
						Team = Team1Count == 0 and 1 or 2
					} )

					self.StartedGame = false

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
	function( self, Gamerules )
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

		local PlayerCount = Shine.GetHumanPlayerCount()
		if PlayerCount < self.Config.MinPlayers then return end

		if Team1Com and Team2Com then
			self:QueueGameStart( Gamerules )
		end
	end
}

function Plugin:UpdatePregame( Gamerules )
	if Gamerules:GetGameState() == kGameState.PreGame then
		return false
	end
end

function Plugin:CheckGameStart( Gamerules )
	local State = Gamerules:GetGameState()

	if State > kGameState.PreGame then return end

	--Do not allow starting too soon.
	local StartDelay = self.Config.StartDelay
	if StartDelay > 0 and SharedTime() < StartDelay then
		return false
	end

	self.UpdateFuncs[ self.Config.Mode ]( self, Gamerules )

	return false
end
