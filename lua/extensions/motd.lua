--[[
	Shine MotD system.
]]

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "MotD.json"

Plugin.Commands = {}

function Plugin:Initialise()
	self:CreateCommands()

	self.Enabled = true
	
	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		MessageText = { "Welcome to my awesome server!", "Admins can be reached @ mywebsite.com", "Have a pleasant stay!" }, --Message lines.
		Delay = 5, --Wait this long after spawning to display the message.
		Accepted = {}
	}

	if Save then
		local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

		if not PluginConfig then
			Notify( "Error writing motd config file: "..Err )	

			return	
		end

		PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

		Notify( "Shine motd config file created." )

		PluginConfig:close()
	end
end

function Plugin:SaveConfig()
	local PluginConfig, Err = io.open( Shine.Config.ExtensionDir..self.ConfigName, "w+" )

	if not PluginConfig then
		Notify( "Error writing motd config file: "..Err )	

		return	
	end

	PluginConfig:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Shine:Print( "Shine motd config file saved." )

	PluginConfig:close()
end

function Plugin:LoadConfig()
	local PluginConfig = io.open( Shine.Config.ExtensionDir..self.ConfigName, "r" )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = Decode( PluginConfig:read( "*all" ) )

	PluginConfig:close()
end

function Plugin:ClientConnect( Client )
	local ID = Client:GetUserId()

	if self.Config.Accepted[ tostring( ID ) ] then return end

	Shine.Timer.Simple( self.Config.Delay, function()
		local Player = Client:GetControllingPlayer()
		if not Player then return end
		
		local Messages = self.Config.MessageText

		for i = 1, #Messages do
			Shine:Notify( Player, Messages[ i ] )
		end
	end )
end

function Plugin:CreateCommands()
	local Commands = self.Commands

	local function MotD( Client )
		if not Client then return end
		
		local Player = Client:GetControllingPlayer()
		if not Player then return end

		local Messages = self.Config.MessageText

		for i = 1, #Messages do
			Shine:Notify( Player, Messages[ i ] )
		end
	end
	Commands.MotDCommand = Shine:RegisterCommand( "sh_motd", "motd", MotD, true )
	Commands.MotDCommand:Help( "Shows the message of the day." )

	local function AcceptMotD( Client )
		if not Client then return end
		
		local Player = Client:GetControllingPlayer()

		if not Player then return end

		local ID = Client:GetUserId()

		if self.Config.Accepted[ tostring( ID ) ] then
			Shine:Notify( Player, "You have already accepted the message of the day." )

			return
		end

		self.Config.Accepted[ tostring( ID ) ] = true
		self:SaveConfig()

		Shine:Notify( Player, "Thank you for accepting the message of the day." )
	end
	Commands.AcceptMotDCommand = Shine:RegisterCommand( "sh_acceptmotd", "acceptmotd", AcceptMotD, true )
	Commands.AcceptMotDCommand:Help( "Accepts the message of the day so you no longer see it on connect." )

	local function ShowMotD( Client, Target )
		local Player = Target:GetControllingPlayer()
		if not Player then return end
		
		local Messages = self.Config.MessageText

		for i = 1, #Messages do
			Shine:Notify( Player, Messages[ i ] )
		end
	end
	Commands.ShowMotDCommand = Shine:RegisterCommand( "sh_showmotd", "showmotd", ShowMotD )
	Commands.ShowMotDCommand:AddParam{ Type = "client" }
	Commands.ShowMotDCommand:Help( "<player name/steam id> Shows the message of the day to the given player." )
end

function Plugin:Cleanup()
	for _, Command in pairs( self.Commands ) do
		Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
	end

	self.Enabled = false
end

Shine:RegisterExtension( "motd", Plugin )
