--[[
	Shine pregame countdown plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "PreGame.json"

function Plugin:Initialise()
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
		RequireComs = 1
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

	if Changed then self:SaveConfig() end

	self.Config.RequireComs = Clamp( Floor( self.Config.RequireComs ), 0, 1 )
end

function Plugin:StartCountdown()
	local Gamerules = GetGamerules()

	if not Gamerules then return end

	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength  
	Gamerules.lastCountdownPlayed = nil

	self.StartedGame = false
	self.GameStarting = false
end

function Plugin:ClientConnect( Client )
	if not self.CountStart then return end
	if not self.Config.ShowCountdown then return end

	local TimeLeft = Ceil( self.CountEnd - Shared.GetTime() )

	if TimeLeft <= 0 or TimeLeft > 5 then return end

	Shine:SendText( Client, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", TimeLeft, 255, 0, 0, 1, 3, 0 ) )
end

function Plugin:SetGameState( Gamerules, State, OldState )
	if State == kGameState.NotStarted then return end
	
	if self.CountStart then
		self.CountStart = nil
		self.CountEnd = nil
		self.SentCountdown = nil
	end

	self.StartedGame = false
	self.GameStarting = false
end

Plugin.UpdateFuncs = {
	--Legacy functionality, fixed time for pregame then start.
	[ 0 ] = function( self, Gamerules )
		if not self.CountStart then
			if MapCycle_TestCycleMap() then return end
			
			local Duration = self.Config.PreGameTime

			self.CountStart = Shared.GetTime()
			self.CountEnd = Shared.GetTime() + Duration

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
	--After the set time, if one team has a commander, start the game.
	[ 1 ] = function( self, Gamerules )
		if not self.CountStart then
			if MapCycle_TestCycleMap() then return end

			local Duration = self.Config.PreGameTime

			self.CountStart = Shared.GetTime()
			self.CountEnd = Shared.GetTime() + Duration

			return
		end

		if self.GameStarting then return end

		local Team1Com = Gamerules.team1:GetCommander()
		local Team2Com = Gamerules.team2:GetCommander()

		--Both teams have a commander, begin countdown.
		if ( Team1Com and Team2Com ) or Shared.GetCheatsEnabled() then
			self.GameStarting = true

			local CountdownTime = self.Config.CountdownTime

			if self.Config.ShowCountdown then
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in "..string.TimeToString( CountdownTime ), 5, 255, 255, 255, 1, 3, 1 ) )
			end

			Shine.Timer.Simple( CountdownTime - 5, function()
				Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", 5, 255, 0, 0, 1, 3, 0 ) )
			end )

			Shine.Timer.Simple( CountdownTime, function()
				self:StartCountdown()
			end )

			return
		end

		local TimeLeft = Ceil( self.CountEnd - Shared.GetTime() )

		--Time's up!
		if TimeLeft <= 0 then
			if Team1Com or Team2Com then --One team has a commander.
				if not self.StartedGame then
					Shine:Notify( nil, "PreGame", Shine.Config.ChatName, "Pregame has exceeded %s and there is one commander. Starting game...", true, string.TimeToString( self.Config.PreGameTime ) )

					self.StartedGame = true

					Shine.Timer.Simple( 5, function()
						self:StartCountdown()
					end )
				end
			end
		end
	end,
}

function Plugin:CheckGameStart()
	local Gamerules = GetGamerules()

	if not Gamerules then return end
	
	if Gamerules:GetGameState() ~= kGameState.NotStarted then return end

	local Ret = self.UpdateFuncs[ self.Config.RequireComs ]( self, Gamerules )

	if Ret then return end

	return false
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "pregame", Plugin )
