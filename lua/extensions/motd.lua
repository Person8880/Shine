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
	if self.Unload then return false, "unable to load MotD plugin." end
	
	self:CreateCommands()

	self.Enabled = true
	
	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Mode = self.TEXT_MODE,
		URL = "http://www.unknownworlds.com/ns2/",
		MessageText = { "Welcome to my awesome server!", "Admins can be reached @ mywebsite.com", "Have a pleasant stay!" }, --Message lines.
		Delay = 5, --Wait this long after spawning to display the message.
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

	Notify( "Shine motd config file saved." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	if self.Config.Mode == self.HTML_MODE then
		if Shine.Config.LegacyMode then
			Shared.Message( "Unable to use HTML mode for MotD when running Shine in legacy mode. Disabling plugin..." )
			self.Unload = true
		else
			self.Unload = nil
		end
	else
		self.Unload = nil
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

function Plugin:ClientConnect( Client )
	if Client:GetIsVirtual() then return end
	
	local ID = Client:GetUserId()

	if self.Config.Accepted[ tostring( ID ) ] then return end

	Shine.Timer.Simple( self.Config.Delay, function()
		if Shine:HasAccess( Client, "sh_showmotd" ) then return end
		
		local Player = Client:GetControllingPlayer()
		if not Player then return end

		self:ShowMotD( Player )
	end )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function MotD( Client )
		if not Client then return end
		
		local Player = Client:GetControllingPlayer()
		if not Player then return end

		self:ShowMotD( Player )
	end
	Commands.MotDCommand = Shine:RegisterCommand( "sh_motd", "motd", MotD, true )
	Commands.MotDCommand:Help( "Shows the message of the day." )

	local function AcceptMotD( Client )
		if not Client then return end
		
		local Player = Client:GetControllingPlayer()

		if not Player then return end

		local ID = Client:GetUserId()

		if self.Config.Accepted[ tostring( ID ) ] then
			Shine:Notify( Player, "MotD", "Admin", "You have already accepted the message of the day." )

			return
		end

		self.Config.Accepted[ tostring( ID ) ] = true
		self:SaveConfig()

		Shine:Notify( Player, "MotD", "Admin", "Thank you for accepting the message of the day." )
	end
	Commands.AcceptMotDCommand = Shine:RegisterCommand( "sh_acceptmotd", "acceptmotd", AcceptMotD, true )
	Commands.AcceptMotDCommand:Help( "Accepts the message of the day so you no longer see it on connect." )

	local function ShowMotD( Client, Target )
		local Player = Target:GetControllingPlayer()
		if not Player then return end
		
		self:ShowMotD( Player )
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
