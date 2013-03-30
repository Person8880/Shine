--[[
	Shine MotD system.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "MotD.json"

Plugin.Commands = {}

Plugin.TEXT_MODE = 1
Plugin.HTML_MODE = 2

function Plugin:Initialise()
	self:CreateCommands()

	self.Enabled = true
	
	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Mode = self.TEXT_MODE,
		URL = "http://www.unknownworlds.com/ns2/",
		MessageText = { "Welcome to my awesome server!", "Admins can be reached @ mywebsite.com", "Have a pleasant stay!" }, --Message lines.
		Accepted = {}
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing motd config file: "..Err )	

			return	
		end

		Notify( "Shine motd config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing motd config file: "..Err )	

		return	
	end

	Notify( "Shine motd config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	local Edited

	if self.Config.Delay then
		self.Config.Delay = nil
		Edited = true
	end

	if Edited then
		self:SaveConfig()
	end
end

function Plugin:ShowMotD( Player )
	if not Player then return end
	
	if self.Config.Mode == self.TEXT_MODE then
		local Messages = self.Config.MessageText

		for i = 1, #Messages do
			Shine:Notify( Player, "", "", Messages[ i ] )
		end

		return
	end

	if self.Config.Mode == self.HTML_MODE then
		Server.SendNetworkMessage( Player, "Shine_Web", { URL = self.Config.URL }, true )
	end
end

function Plugin:ClientConfirmConnect( Client )
	if Client:GetIsVirtual() then return end
	
	local ID = Client:GetUserId()

	if self.Config.Accepted[ tostring( ID ) ] then return end

	if Shine:HasAccess( Client, "sh_showmotd" ) then return end

	self:ShowMotD( Client )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function MotD( Client )
		if not Client then return end

		self:ShowMotD( Client )
	end
	Commands.MotDCommand = Shine:RegisterCommand( "sh_motd", "motd", MotD, true )
	Commands.MotDCommand:Help( "Shows the message of the day." )

	local function AcceptMotD( Client )
		if not Client then return end

		local ID = Client:GetUserId()

		if self.Config.Accepted[ tostring( ID ) ] then
			Shine:Notify( Client, "MotD", Shine.Config.ChatName, "You have already accepted the message of the day." )

			return
		end

		self.Config.Accepted[ tostring( ID ) ] = true
		self:SaveConfig()

		Shine:Notify( Client, "MotD", Shine.Config.ChatName, "Thank you for accepting the message of the day." )
	end
	Commands.AcceptMotDCommand = Shine:RegisterCommand( "sh_acceptmotd", "acceptmotd", AcceptMotD, true )
	Commands.AcceptMotDCommand:Help( "Accepts the message of the day so you no longer see it on connect." )

	local function ShowMotD( Client, Target )
		self:ShowMotD( Target )
	end
	Commands.ShowMotDCommand = Shine:RegisterCommand( "sh_showmotd", "showmotd", ShowMotD )
	Commands.ShowMotDCommand:AddParam{ Type = "client" }
	Commands.ShowMotDCommand:Help( "<player> Shows the message of the day to the given player." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "motd", Plugin )
