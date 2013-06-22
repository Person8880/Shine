--[[
	Shine welcome message plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local Encode, Decode = json.encode, json.decode
local StringFormat = string.format
local TableEmpty = table.Empty

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "WelcomeMessages.json"

Plugin.Welcomed = {}

local DefaultConfig = {
	MessageDelay = 5,
	Users = {
		[ "90000001" ] = { Welcome = "Bob has joined the party!", Leave = "Bob is off to fight more important battles." }
	},
	ShowGeneric = false
}

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = DefaultConfig

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

	if self.Config.ShowGeneric == nil then
		self.Config.ShowGeneric = false
		
		self:SaveConfig()
	end
end

function Plugin:ClientConnect( Client )
	Shine.Timer.Simple( self.Config.MessageDelay, function()
		if not Shine:IsValidClient( Client ) then return end
		
		local ID = Client:GetUserId()

		local MessageTable = self.Config.Users[ tostring( ID ) ]

		if MessageTable and MessageTable.Welcome and not MessageTable.Said then
			Shine:Notify( nil, "", "", MessageTable.Welcome )

			MessageTable.Said = true

			self.Welcomed[ Client ] = true

			self:SaveConfig()
		
			return
		end

		if not self.Config.ShowGeneric then return end

		local Player = Client:GetControllingPlayer()

		if not Player then return end

		self.Welcomed[ Client ] = true

		Shine:Notify( nil, "", "", "%s has joined the game.", true, Player:GetName() )
	end )
end

function Plugin:ClientDisconnect( Client )
	if not self.Welcomed[ Client ] then return end

	self.Welcomed[ Client ] = nil
	
	local ID = Client:GetUserId()

	local MessageTable = self.Config.Users[ tostring( ID ) ]

	if MessageTable and MessageTable.Leave then
		Shine:Notify( nil, "", "", MessageTable.Leave )

		MessageTable.Said = nil
		
		self:SaveConfig()

		return
	end

	if not self.Config.ShowGeneric then return end

	local Player = Client:GetControllingPlayer()

	if not Player then return end
	
	Shine:Notify( nil, "", "", "%s has left the game.", true, Player:GetName() )
end

function Plugin:Cleanup()
	TableEmpty( self.Welcomed )

	self.Enabled = false
end

Shine:RegisterExtension( "welcomemessages", Plugin )
