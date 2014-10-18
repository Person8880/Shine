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
Plugin.Version = "1.5"

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

	Shine:SendText( Client, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s",
		TimeLeft, 255, 0, 0, 1, 3, 0 ) )
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

Plugin.UpdateFuncs = {
	--Legacy functionality, fixed time for pregame then start.
	[ 0 ] = function( self, Gamerules )
		local Team1 = Gamerules.team1
		local Team2 = Gamerules.team2

		local Team1Count = Team1:GetNumPlayers()
		local Team2Count = Team2:GetNumPlayers()

		if Team1Count == 0 or Team2Count == 0 then
			if self.CountStart then
				self.CountStart = nil
				self.CountEnd = nil
				self.SentCountdown = nil

				Gamerules:SetGameState( kGameState.NotStarted )

				self:Notify( nil, "Game start aborted, %s is empty.", true,
					Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
					or Shine:GetTeamName( 2, nil, true ) )
			end

			return
		end

		if not self.CountStart then
			--if MapCycle_TestCycleMap() then return end

			local Duration = self.Config.PreGameTime

			self.CountStart = SharedTime()
			self.CountEnd = SharedTime() + Duration

			self.GameStarting = true

			Gamerules:SetGameState( kGameState.PreGame )

			if self.Config.ShowCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
					"Game starts in "..string.TimeToString( Duration ), 5,
					255, 255, 255, 1, 3, 1 ) )
			end

			return
		end

		local TimeLeft = Ceil( self.CountEnd - SharedTime() )

		if TimeLeft == 5 then
			if self.Config.ShowCountdown and not self.SentCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
					"Game starts in %s", TimeLeft, 255, 0, 0, 1, 3, 0 ) )
				self.SentCountdown = true
			end
		end

		if self.CountEnd <= SharedTime() then
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

				Shine:RemoveText( nil, { ID = 2 } )

				self:Notify( nil, "Game start aborted, a commander dropped out." )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )

				return
			end

			if Team1Count == 0 or Team2Count == 0 then
				self:DestroyTimers()

				Shine:RemoveText( nil, { ID = 2 } )

				self:Notify( nil, "Game start aborted, %s is empty.", true,
					Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
					or Shine:GetTeamName( 2, nil, true ) )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )

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
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
					"Game starts in "..string.TimeToString( CountdownTime ),
					5, 255, 255, 255, 1, 3, 1 ) )
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

				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
					"Game starts in %s", 5, 255, 0, 0, 1, 3, 0 ) )
			end )

			self:CreateTimer( self.CountdownTimer, CountdownTime, 1, function()
				local Team1Com = Team1:GetCommander()
				local Team2Com = Team2:GetCommander()

				if self.Config.AbortIfNoCom then
					if not Team1Com or not Team2Com then
						self:Notify( nil, "Game start aborted, a commander dropped out." )

						self.GameStarting = false

						Gamerules:SetGameState( kGameState.NotStarted )

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then
					self:Notify( nil, "Game start aborted, %s is empty.", true,
						Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
						or Shine:GetTeamName( 2, nil, true ) )

					self.GameStarting = false

					Gamerules:SetGameState( kGameState.NotStarted )

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

				self:Notify( nil, "Game start aborted, %s is empty.", true,
					Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
					or Shine:GetTeamName( 2, nil, true ) )

				Gamerules:SetGameState( kGameState.NotStarted )

				Shine:RemoveText( nil, { ID = 2 } )
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

					Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
						Message, 5, 255, 255, 255, 1, 3, 1 ) )
				end
			end
		else
			if self.Config.AbortIfNoCom and self.CountStart then
				self.CountStart = nil
				self.CountEnd = nil

				Gamerules:SetGameState( kGameState.NotStarted )

				self:Notify( nil, "Game start aborted, a commander dropped out." )

				Shine:RemoveText( nil, { ID = 2 } )
			end
		end

		if not self.CountEnd then return end

		if self.GameStarting then return end

		local TimeLeft = Ceil( self.CountEnd - Time )

		if TimeLeft == 5 then
			if self.Config.ShowCountdown and not self.SentCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
					"Game starts in %s", TimeLeft, 255, 0, 0, 1, 3, 0 ) )

				Gamerules:SetGameState( kGameState.PreGame )

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

	--After the set time, if one team has a commander, start the game.
	[ 2 ] = function( self, Gamerules )
		if not self.CountStart then
			--if MapCycle_TestCycleMap() then return end

			local Duration = self.Config.PreGameTime

			self.CountStart = SharedTime()
			self.CountEnd = SharedTime() + Duration

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

				Shine:RemoveText( nil, { ID = 2 } )

				self:Notify( nil, "Game start aborted, a commander dropped out." )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )
			end

			if Team1Count == 0 or Team2Count == 0 then
				self:DestroyTimers()

				Shine:RemoveText( nil, { ID = 2 } )

				self:Notify( nil, "Game start aborted, a commander dropped out." )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )
			end

			return
		end

		--Both teams have a commander, begin countdown.
		if Team1Com and Team2Com and not self.StartedGame then
			self.GameStarting = true

			Gamerules:SetGameState( kGameState.PreGame )

			local CountdownTime = self.Config.CountdownTime

			if self.Config.ShowCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
					"Game starts in "..string.TimeToString( CountdownTime ),
					5, 255, 255, 255, 1, 3, 1 ) )
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

				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7,
					"Game starts in %s", 5, 255, 0, 0, 1, 3, 0 ) )
			end )

			self:CreateTimer( self.CountdownTimer, CountdownTime, 1, function()
				local Team1Com = Team1:GetCommander()
				local Team2Com = Team2:GetCommander()

				if self.Config.AbortIfNoCom then
					if not Team1Com or not Team2Com then
						self:Notify( nil, "Game start aborted, a commander dropped out." )

						self.GameStarting = false

						Gamerules:SetGameState( kGameState.NotStarted )

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then
					self:Notify( nil, "Game start aborted, %s is empty.", true,
						Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
						or Shine:GetTeamName( 2, nil, true ) )

					self.GameStarting = false

					Gamerules:SetGameState( kGameState.NotStarted )

					return
				end

				self:StartCountdown()
			end )

			return
		end

		local TimeLeft = Ceil( self.CountEnd - SharedTime() )

		--Time's up!
		if TimeLeft <= 0 then
			if Team1Com or Team2Com then --One team has a commander.
				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then return end

				if not self.StartedGame then
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
								self:Notify( nil, "Game start aborted, a commander dropped out." )

								self.StartedGame = false

								Gamerules:SetGameState( kGameState.NotStarted )

								return
							end
						end

						local Team1Count = Team1:GetNumPlayers()
						local Team2Count = Team2:GetNumPlayers()

						if Team1Count == 0 or Team2Count == 0 then
							self:Notify( nil, "Game start aborted, %s is empty.", true,
								Team1Count == 0 and Shine:GetTeamName( 1, nil, true )
								or Shine:GetTeamName( 2, nil, true ) )

							self.StartedGame = false

							Gamerules:SetGameState( kGameState.NotStarted )

							return
						end

						self:StartCountdown()
					end )
				end
			end
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
