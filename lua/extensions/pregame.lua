--[[
	Shine pregame countdown plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.5"

Plugin.HasConfig = true
Plugin.ConfigName = "PreGame.json"

Plugin.FiveSecTimer = "PreGameFiveSeconds"
Plugin.CountdownTimer = "PreGameCountdown"

function Plugin:Initialise()
	local GetMod = Server.GetActiveModId

	for i = 1, Server.GetNumActiveMods() do
		local Mod = GetMod( i )

		if Mod == "5f35045" then return false, "Pregame plugin does not work with combat." end
	end

	self.CountStart = nil
	self.CountEnd = nil
	self.GameStarting = false
	self.StartedGame = false

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		PreGameTime = 45,
		CountdownTime = 15,
		ShowCountdown = true,
		RequireComs = 1,
		AbortIfNoCom = false
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing pregame config file: "..Err )	

			return	
		end

		Notify( "Shine pregame config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing pregame config file: "..Err )

		return	
	end

	Notify( "Shine pregame config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	local Changed

	if self.Config.RequireComs == nil then
		self.Config.RequireComs = 1
		Changed = true
	end

	if self.Config.CountdownTime == nil then
		self.Config.CountdownTime = 15
		Changed = true
	end

	if self.Config.AbortIfNoCom == nil then
		self.Config.AbortIfNoCom = false
		Changed = true
	end

	if Changed then self:SaveConfig() end

	self.Config.RequireComs = Clamp( Floor( self.Config.RequireComs ), 0, 2 )
end

function Plugin:StartCountdown()
	local Gamerules = GetGamerules()

	if not Gamerules then return end

	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength  
	Gamerules.lastCountdownPlayed = nil

	for _, Player in ientitylist( Shared.GetEntitiesWithClassname( "Player" ) ) do
		if Player.ResetScores then
			Player:ResetScores()
		end
	end

	self.StartedGame = false
	self.GameStarting = false
end

function Plugin:ClientConfirmConnect( Client )
	if not self.CountStart then return end
	if not self.Config.ShowCountdown then return end

	local TimeLeft = Ceil( self.CountEnd - Shared.GetTime() )

	if TimeLeft <= 0 or TimeLeft > 5 then return end

	Shine:SendText( Client, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", TimeLeft, 255, 0, 0, 1, 3, 0 ) )
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
end

function Plugin:DestroyTimers()
	if Shine.Timer.Exists( self.FiveSecTimer ) then
		Shine.Timer.Destroy( self.FiveSecTimer )
	end

	if Shine.Timer.Exists( self.CountdownTimer ) then
		Shine.Timer.Destroy( self.CountdownTimer )
	end
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

				Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, %s is empty.", true, Team1Count == 0 and "marine team" or "alien team" )
			end

			return 
		end

		if not self.CountStart then
			if MapCycle_TestCycleMap() then return end
			
			local Duration = self.Config.PreGameTime

			self.CountStart = Shared.GetTime()
			self.CountEnd = Shared.GetTime() + Duration

			self.GameStarting = true

			Gamerules:SetGameState( kGameState.PreGame )

			if self.Config.ShowCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in "..string.TimeToString( Duration ), 5, 255, 255, 255, 1, 3, 1 ) )
			end

			return
		end

		local TimeLeft = Ceil( self.CountEnd - Shared.GetTime() )

		if TimeLeft == 5 then
			if self.Config.ShowCountdown and not self.SentCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", TimeLeft, 255, 0, 0, 1, 3, 0 ) )
				self.SentCountdown = true
			end
		end

		if self.CountEnd <= Shared.GetTime() then
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

		local Time = Shared.GetTime()

		if self.GameStarting then
			if self.Config.AbortIfNoCom and ( not Team1Com or not Team2Com ) then
				self:DestroyTimers()

				Shine:RemoveText( nil, { ID = 2 } )

				Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, a commander dropped out." )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )

				return
			end

			if Team1Count == 0 or Team2Count == 0 then
				self:DestroyTimers()

				Shine:RemoveText( nil, { ID = 2 } )

				Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, %s is empty.", true, Team1Count == 0 and "marine team" or "alien team" )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )

				if self.CountStart then
					self.CountStart = nil
					self.CountEnd = nil
				end

				return
			end
		end

		--Both teams have a commander, begin countdown, but only if the 1 commander countdown isn't past the 2 commander countdown time length left.
		if Team1Com and Team2Com and not self.GameStarting and not ( self.CountEnd and self.CountEnd - Time <= self.Config.CountdownTime ) then
			self.GameStarting = true

			Gamerules:SetGameState( kGameState.PreGame )

			local CountdownTime = self.Config.CountdownTime

			if self.Config.ShowCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in "..string.TimeToString( CountdownTime ), 5, 255, 255, 255, 1, 3, 1 ) )
			end

			Shine.Timer.Create( self.FiveSecTimer, CountdownTime - 5, 1, function()
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

				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", 5, 255, 0, 0, 1, 3, 0 ) )
			end )

			Shine.Timer.Create( self.CountdownTimer, CountdownTime, 1, function()
				local Team1Com = Team1:GetCommander()
				local Team2Com = Team2:GetCommander()

				if self.Config.AbortIfNoCom then
					if not Team1Com or not Team2Com then
						Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, a commander dropped out." )

						self.GameStarting = false

						Gamerules:SetGameState( kGameState.NotStarted )

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then 
					Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, %s is empty.", true, Team1Count == 0 and "marine team" or "alien team" )

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

				Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, %s is empty.", true, Team1Count == 0 and "marine team" or "alien team" )

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
					local Message = StringFormat( "%s have a commander. %s have %s to choose their commander.", 
						Team1Com and "Marines" or "Aliens", Team1Com and "Aliens" or "Marines", string.TimeToString( Duration ) )

					Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, Message, 5, 255, 255, 255, 1, 3, 1 ) )
				end
			end
		else
			if self.Config.AbortIfNoCom and self.CountStart then
				self.CountStart = nil
				self.CountEnd = nil

				Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, a commander dropped out." )

				Shine:RemoveText( nil, { ID = 2 } )
			end
		end

		if not self.CountEnd then return end

		if self.GameStarting then return end

		local TimeLeft = Ceil( self.CountEnd - Time )

		if TimeLeft == 5 then
			if self.Config.ShowCountdown and not self.SentCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", TimeLeft, 255, 0, 0, 1, 3, 0 ) )
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
			if MapCycle_TestCycleMap() then return end

			local Duration = self.Config.PreGameTime

			self.CountStart = Shared.GetTime()
			self.CountEnd = Shared.GetTime() + Duration

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

				Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, a commander dropped out." )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )
			end

			if Team1Count == 0 or Team2Count == 0 then
				self:DestroyTimers()

				Shine:RemoveText( nil, { ID = 2 } )

				Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, a commander dropped out." )

				self.GameStarting = false

				Gamerules:SetGameState( kGameState.NotStarted )
			end

			return
		end

		--Both teams have a commander, begin countdown.
		if Team1Com and Team2Com then
			self.GameStarting = true

			Gamerules:SetGameState( kGameState.PreGame )

			local CountdownTime = self.Config.CountdownTime

			if self.Config.ShowCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in "..string.TimeToString( CountdownTime ), 5, 255, 255, 255, 1, 3, 1 ) )
			end

			Shine.Timer.Create( self.FiveSecTimer, CountdownTime - 5, 1, function()
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

				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", 5, 255, 0, 0, 1, 3, 0 ) )
			end )

			Shine.Timer.Create( self.CountdownTimer, CountdownTime, 1, function()
				local Team1Com = Team1:GetCommander()
				local Team2Com = Team2:GetCommander()

				if self.Config.AbortIfNoCom then
					if not Team1Com or not Team2Com then
						Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, a commander dropped out." )

						self.GameStarting = false

						Gamerules:SetGameState( kGameState.NotStarted )

						return
					end
				end

				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then 
					Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, %s is empty.", true, Team1Count == 0 and "marine team" or "alien team" )

					self.GameStarting = false

					Gamerules:SetGameState( kGameState.NotStarted )

					return 
				end

				self:StartCountdown()
			end )

			return
		end

		local TimeLeft = Ceil( self.CountEnd - Shared.GetTime() )

		--Time's up!
		if TimeLeft <= 0 then
			if Team1Com or Team2Com then --One team has a commander.
				local Team1Count = Team1:GetNumPlayers()
				local Team2Count = Team2:GetNumPlayers()

				if Team1Count == 0 or Team2Count == 0 then return end

				if not self.StartedGame then
					Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Pregame has exceeded %s and there is one commander. Starting game...", true, string.TimeToString( self.Config.PreGameTime ) )

					self.StartedGame = true

					Shine.Timer.Simple( 5, function()
						local Team1Com = Team1:GetCommander()
						local Team2Com = Team2:GetCommander()

						if self.Config.AbortIfNoCom then
							if not Team1Com and not Team2Com then
								Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, a commander dropped out." )

								self.StartedGame = false

								return
							end
						end

						local Team1Count = Team1:GetNumPlayers()
						local Team2Count = Team2:GetNumPlayers()

						if Team1Count == 0 or Team2Count == 0 then 
							Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Game start aborted, %s is empty.", true, Team1Count == 0 and "marine team" or "alien team" )

							self.StartedGame = false

							return 
						end

						self:StartCountdown()
					end )
				end
			end
		end
	end,
}

function Plugin:UpdatePregame()
	local Gamerules = GetGamerules()

	if not Gamerules then return end
	
	if Gamerules:GetGameState() == kGameState.PreGame then
		return false
	end
end

function Plugin:CheckGameStart()
	local Gamerules = GetGamerules()

	if not Gamerules then return end
	
	local State = Gamerules:GetGameState()

	if State ~= kGameState.NotStarted and State ~= kGameState.PreGame then return end

	self.UpdateFuncs[ self.Config.RequireComs ]( self, Gamerules )

	return false
end

function Plugin:Cleanup()
	self:DestroyTimers()
	
	self.Enabled = false
end

Shine:RegisterExtension( "pregame", Plugin )
