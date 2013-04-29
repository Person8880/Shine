--[[
	Shine ready room plugin.

	Allows for setting a max idle time in the ready room, disabling the spectator mode etc.
]]

local Shine = Shine

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "ReadyRoom.json"

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		MaxIdleTime = 120, --Max time in seconds to allow sitting in the ready room.
		TimeToBlockF4 = 120, --Time to block going back to the ready room after being forced out of it.
		DisableSpectate = false, --Disable spectate?
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing readyroom config file: "..Err )	

			return	
		end

		Notify( "Shine readyroom config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing readyroom config file: "..Err )

		return	
	end

	Notify( "Shine readyroom config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

--Prevent players from joining the spectator team, and prevent going back to the ready room after being forced out of it.
function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if NewTeam ~= kSpectatorIndex then return end
	if not self.Config.DisableSpectate then return end

	return false
end

Shine:RegisterExtension( "readyroom", Plugin )
