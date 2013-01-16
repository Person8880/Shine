--[[
	Shine welcome message plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "WelcomeMessages.json"

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		MessageDelay = 5,
		Users = {
			[ "90000001" ] = { Welcome = "Bob has joined the party!", Leave = "Bob is off to fight more important battles." }
		}
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing welcomemessages config file: "..Err )	

			return	
		end

		Notify( "Shine welcomemessages config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing welcomemessages config file: "..Err )	

		return	
	end
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

function Plugin:ClientConnect( Client )
	local ID = Client:GetUserId()

	local MessageTable = self.Config.Users[ tostring( ID ) ]

	if MessageTable and MessageTable.Welcome and not MessageTable.Said then
		Shine.Timer.Simple( self.Config.MessageDelay, function()
			Shine:Notify( nil, "", "", MessageTable.Welcome )
			MessageTable.Said = true
			self:SaveConfig()
		end )
	end
end

function Plugin:ClientDisconnect( Client )
	local ID = Client:GetUserId()

	local MessageTable = self.Config.Users[ tostring( ID ) ]

	if MessageTable and MessageTable.Leave then
		Shine:Notify( nil, "", "", MessageTable.Leave )
		MessageTable.Said = nil
		self:SaveConfig()
	end
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "welcomemessages", Plugin )
