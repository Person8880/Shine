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

Plugin.DefaultConfig = {
	PreGameTime = 45,
	CountdownTime = 15,
	StartDelay = 0,
	ShowCountdown = true,
	RequireComs = 1,
	AbortIfNoCom = false,
	AllowAttackPreGame = true
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.FiveSecTimer = "PreGameFiveSeconds"
Plugin.CountdownTimer = "PreGameCountdown"

Plugin.StartNagInterval = 10

Shine.Hook.SetupClassHook( "Player", "GetCanAttack",
	"CheckPlayerCanAttack", "ActivePre" )

function Plugin:Initialise()
	local Gamemode = Shine.GetGamemode()

	if Gamemode ~= "ns2" and Gamemode ~= "mvm" then
		return false, StringFormat( "The pregame plugin does not work with %s.", Gamemode )
	end

	self.Config.RequireComs = Clamp( Floor( self.Config.RequireComs ), 0, 2 )

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

	Shine.ScreenText.Add( 2, {
		X = 0.5, Y = 0.7,
		Text = "Game starts in %s",
		Duration = TimeLeft,
		R = 255, G = 0, B = 0,
		Alignment = 1,
		Size = 3,
		FadeIn = 0
	}, Client )
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
	if State == kGameState.NotStarted or State == kGameState.PreGame then return end

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

function Plugin:Notify( Player, Message, Format, ... )
	Shine:NotifyDualColour( Player, 100, 100, 255, "[Pre Game]", 255, 255, 255,
		Message, Format, ... )
end

function Plugin:AbortGameStart( Gamerules, Message, Format, ... )
	Gamerules:SetGameState( kGameState.NotStarted )

	self:Notify( nil, Message, Format, ... )

	Shine.ScreenText.End( 2 )
end

function Plugin:ShowGameStart( TimeTillStart, Red )
	if self.Config.ShowCountdown then
		Shine.ScreenText.Add( 2, {
			X = 0.5, Y = 0.7,
			Text = "Game starts in "..string.TimeToString( TimeTillStart ),
			Duration = 5,
			R = 255, G = 255, B = 255,
			Alignment = 1,
			Size = 3,
			FadeIn = 1
		} )
	end
end

function Plugin:ShowCountdown()
	Shine.ScreenText.Add( 2, {
		X = 0.5, Y = 0.7,
		Text = "Game starts in %s",
		Duration = 5,
		R = 255, G = 0, B = 0,
		Alignment = 1,
		Size = 3,
		FadeIn = 0
	} )
end

function Plugin:SendStartNag( Message )
	self:SendNetworkMessage( nil, "StartNag", {
		Message = Message
	}, true )
end

function Plugin:NagForTeam( WaitingForTeam )
	local TeamName = Shine:GetTeamName( WaitingForTeam, true )
	self:SendStartNag( StringFormat( "Waiting on %s to choose a commander", TeamName ) )
end

function Plugin:NagForBoth()
	self:SendStartNag( "Waiting on both teams to choose a commander" )
end

Plugin.UpdateFuncs = {
	--Legacy functionality, fixed time for pregame then start.
	[ 0 ] = function( self, Gamerules )
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

				self:AbortGameStart( Gamerules, "Game start aborted, %s is empty.", true,
					Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
					or Shine:GetTeamName( 2, nil, true ) )
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
				Shine.ScreenText.Add( 2, {
					X = 0.5, Y = 0.7,
					Text = "Game starts in %s",
					Duration = TimeLeft,
					R = 255, G = 0, B = 0,
					Alignment = 1,
					Size = 3,
					FadeIn = 0
				} )
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
	[ 1 ] = function( self, Gamerules )
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Com = Team1:GetCommander()
		local Team2Com = Team2:GetCommander()

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		local Time = SharedTime()

		if self.GameStarting then
			if self.Config.AbortIfNoCom and ( not Team1Com or not Team2Com ) then
				self:DestroyTimers()
				self:AbortGameStart( Gamerules, "Game start aborted, a commander dropped out." )
				self.GameStarting = false

				return
			end

			if Team1Count == 0 or Team2Count == 0 then
				self:DestroyTimers()

				self:AbortGameStart( Gamerules, "Game start aborted, %s is empty.", true,
					Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
					or Shine:GetTeamName( 2, nil, true ) )

				self.GameStarting = false

				if self.CountStart then
					self.CountStart = nil
					self.CountEnd = nil
				end

				return
			end

			return
		end

		--Both teams have a commander, begin countdown,
		--but only if the 1 commander countdown isn't past the 2
		--commander countdown time length left.
		if Team1Com and Team2Com and not self.GameStarting
		and not ( self.CountEnd and self.CountEnd - Time <= self.Config.CountdownTime ) then
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
						self:AbortGameStart( Gamerules,
							"Game start aborted, a commander dropped out." )

						self.GameStarting = false

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then
					self:AbortGameStart( Gamerules, "Game start aborted, %s is empty.", true,
						Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
						or Shine:GetTeamName( 2, nil, true ) )

					self.GameStarting = false

					return
				end

				self:StartCountdown()
			end )

			return
		end

		--A team no longer has players, abort the timer.
		if Team1Count == 0 or Team2Count == 0 then
			if self.CountStart then
				self.CountStart = nil
				self.CountEnd = nil

				self:AbortGameStart( Gamerules, "Game start aborted, %s is empty.", true,
					Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
					or Shine:GetTeamName( 2, nil, true ) )
			end

			return
		end

		if Team1Com or Team2Com then
			if not self.CountStart then
				local Duration = self.Config.PreGameTime

				self.CountStart = Time
				self.CountEnd = Time + Duration

				if self.Config.ShowCountdown then
					local Team1Name = Shine:GetTeamName( 1, true )
					local Team2Name = Shine:GetTeamName( 2, true )

					local Message = StringFormat(
						"%s have a commander. %s have %s to choose their commander.",
						Team1Com and Team1Name or Team2Name,
						Team1Com and Team2Name or Team1Name,
						string.TimeToString( Duration ) )

					Shine.ScreenText.Add( 2, {
						X = 0.5, Y = 0.7,
						Text = Message,
						Duration = 5,
						R = 255, G = 255, B = 255,
						Alignment = 1,
						Size = 3,
						FadeIn = 1
					} )
				end
			end
		else
			if self.Config.AbortIfNoCom and self.CountStart then
				self.CountStart = nil
				self.CountEnd = nil

				self:AbortGameStart( Gamerules, "Game start aborted, a commander dropped out." )
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
	[ 2 ] = function( self, Gamerules )
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
			if self.Config.AbortIfNoCom and ( not Team1Com or not Team2Com ) then
				self:DestroyTimers()

				self:AbortGameStart( Gamerules, "Game start aborted, a commander dropped out." )
				self.GameStarting = false
			end

			if Team1Count == 0 or Team2Count == 0 then
				self:DestroyTimers()

				self:AbortGameStart( Gamerules, "Game start aborted, a commander dropped out." )
				self.GameStarting = false
			end

			return
		end

		--Both teams have a commander, begin countdown.
		if Team1Com and Team2Com and not self.StartedGame then
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
						self:AbortGameStart( Gamerules,
							"Game start aborted, a commander dropped out." )
						self.GameStarting = false

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then
					self:AbortGameStart( Gamerules, "Game start aborted, %s is empty.", true,
						Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
						or Shine:GetTeamName( 2, nil, true ) )

					self.GameStarting = false

					return
				end

				self:StartCountdown()
			end )

			return
		end

		local TimeLeft = Ceil( self.CountEnd - Time )

		--Time's up!
		if TimeLeft <= 0 and ( Team1Com or Team2Com ) then
			local Team1Count = Team1:GetNumPlayers()
			local Team2Count = Team2:GetNumPlayers()

			if Team1Count == 0 or Team2Count == 0 then return end
			if self.StartedGame then return end

			self:Notify( nil,
				"Pregame has exceeded %s and there is one commander. Starting game...",
				true, string.TimeToString( self.Config.PreGameTime ) )

			self.StartedGame = true

			Gamerules:SetGameState( kGameState.PreGame )

			self:SimpleTimer( 5, function()
				local Team1Com = Team1:GetCommander()
				local Team2Com = Team2:GetCommander()

				if self.Config.AbortIfNoCom then
					if not Team1Com and not Team2Com then
						self:AbortGameStart( Gamerules,
							"Game start aborted, a commander dropped out." )

						self.StartedGame = false

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then
					self:AbortGameStart( Gamerules, "Game start aborted, %s is empty.",
						true, Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
						or Shine:GetTeamName( 2, nil, true ) )

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
}

function Plugin:UpdatePregame( Gamerules )
	if Gamerules:GetGameState() == kGameState.PreGame then
		return false
	end
end

function Plugin:CheckGameStart( Gamerules )
	local State = Gamerules:GetGameState()

	if State ~= kGameState.NotStarted and State ~= kGameState.PreGame then return end

	--Do not allow starting too soon.
	local StartDelay = self.Config.StartDelay
	if StartDelay > 0 and SharedTime() < StartDelay then
		return false
	end

	self.UpdateFuncs[ self.Config.RequireComs ]( self, Gamerules )

	return false
end
