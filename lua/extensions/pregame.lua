--[[
	Shine pregame countdown plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local Ceil = math.ceil

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "PreGame.json"

function Plugin:Initialise()
	self.CountStart = nil
	self.CountEnd = nil

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		PreGameTime = 45,
		ShowCountdown = true
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

	Notify( "Shine pregame config file saved." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

function Plugin:StartCountdown()
	local Gamerules = GetGamerules()

	if not Gamerules then return end

	Gamerules:ResetGame()
	Gamerules:SetGameState( kGameState.Countdown )
	Gamerules.countdownTime = kCountDownLength  
	Gamerules.lastCountdownPlayed = nil
end

function Plugin:ClientConnect( Client )
	if not self.CountStart then return end
	if not self.Config.ShowCountdown then return end

	local TimeLeft = Ceil( self.CountEnd - Shared.GetTime() )

	if TimeLeft <= 0 or TimeLeft > 5 then return end

	Shine:SendText( Client, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", TimeLeft, 255, 0, 0, 1, 2 ) )
end

function Plugin:UpdatePregame()
	local Gamerules = GetGamerules()

	if not Gamerules then return end
	
	if Gamerules:GetGameState() ~= kGameState.PreGame then return end

	if not self.CountStart then
		if MapCycle_TestCycleMap() then return end
		
		local Duration = self.Config.PreGameTime

		self.CountStart = Shared.GetTime()
		self.CountEnd = Shared.GetTime() + Duration

		if self.Config.ShowCountdown then
			Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in "..string.TimeToString( Duration ), 5, 255, 255, 255, 1, 2 ) )
		end

		return false
	end

	local TimeLeft = Ceil( self.CountEnd - Shared.GetTime() )

	if TimeLeft == 5 then
		if self.Config.ShowCountdown then
			Shine:SendText( nil, Shine.BuildScreenMessage( 2, 0.5, 0.7, "Game starts in %s", TimeLeft, 255, 0, 0, 1, 2 ) )
		end
	end

	if self.CountEnd <= Shared.GetTime() then
		self.CountStart = nil
		self.CountEnd = nil
		self:StartCountdown()

		return false
	end

	return false
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "pregame", Plugin )
