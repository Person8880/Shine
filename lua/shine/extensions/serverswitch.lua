--[[
	Shine multi-server plugin.
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
	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Servers = {
			{ Name = "My awesome server", IP = "127.0.0.1", Port = "27015", Password = "" }
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

	Notify( "Shine serverswitch config file updated." )
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

		if ServerData.UsersOnly then
			local UserTable = Shine:GetUserData( Client )

			if not UserTable then
				Shine:Notify( Player, "Error", Shine.Config.ChatName, "You are not allowed to switch to that server." )

				return
			end
		end

		local Password = ServerData.Password

		if not Password then 
			Password = ""
		elseif Password ~= "" then
			Password = " "..Password
		end
		
		Server.SendNetworkMessage( Player, "Shine_Command", { 
			Command = StringFormat( "connect %s:%s%s", ServerData.IP, ServerData.Port, Password )
		}, true )
	end
	Commands.SwitchServerCommand = Shine:RegisterCommand( "sh_switchserver", "server", SwitchServer, true )
	Commands.SwitchServerCommand:AddParam{ Type = "number", Min = 1, Round = true, Error = "Please specify a server number to switch to." }
	Commands.SwitchServerCommand:Help( "<number> Connects you to the given registered server." )

	local function ListServers( Client )
		local ServerData = self.Config.Servers

		if #ServerData == 0 then
			if Client then
				ServerAdminPrint( Client, "There are no registered servers." )
			else
				Notify( "There are no registered servers." )
			end

			return
		end

		for i = 1, #ServerData do
			local Data = ServerData[ i ]

			local String = StringFormat( "%i) - %s | %s:%s", i, Data.Name or "No name", Data.IP, Data.Port )

			if Client then
				ServerAdminPrint( Client, String )
			else
				Notify( String )
			end
		end
	end
	Commands.ListServers = Shine:RegisterCommand( "sh_listservers", nil, ListServers, true )
	Commands.ListServers:Help( "Lists all registered servers that you can connect to." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "serverswitch", Plugin )
