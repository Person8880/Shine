--[[
	Shine multi-server plugin.

	I was hoping to be able to query the server data directly from NS2's web admin, but it seems the HTTP functions can't do user authentication.
	So this plugin, for now, is just a way to get players to connect to another server you host.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ServerSwitch.json"

function Plugin:Initialise()
	if Shine.Config.LegacyMode then return false, "cannot operate in legacy mode." end
	
	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Servers = {
			{ IP = "127.0.0.1", Port = "27015" }
		}
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing serverswitch config file: "..Err )	

			return	
		end

		Notify( "Shine serverswitch config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing serverswitch config file: "..Err )	

		return	
	end

	Notify( "Shine serverswitch config file saved." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

function Plugin:CreateCommands()
	self.Commands = {}
	local Commands = self.Commands

	local function SwitchServer( Client, Num )
		if not Client then return end
		local Player = Client:GetControllingPlayer()

		if not Player then return end
		
		local ServerData = self.Config.Servers[ Num ]

		if not ServerData then
			Shine:Notify( Player, "Error", Shine.Config.ChatName, "Invalid server number." )
			return
		end

		Server.SendNetworkMessage( Player, "Shine_Command", { Command = "connect "..ServerData.IP..":"..ServerData.Port }, true )
	end
	Commands.SwitchServerCommand = Shine:RegisterCommand( "sh_switchserver", "server", SwitchServer, true )
	Commands.SwitchServerCommand:AddParam{ Type = "number", Min = 1, Round = true, Error = "Please specify a server number to switch to." }
	Commands.SwitchServerCommand:Help( "<number> Connects you to the given registered server." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "serverswitch", Plugin )
