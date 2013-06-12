--[[
	Reserved slots.

	Currently only the crude password method. I'll expand it if UWE ever get a proper connection event.
]]

local Shine = Shine

local Notify = Shared.Message
local StringFormat = string.format
local TableCount = table.Count

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ReservedSlots.json"

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:GenerateDefaultConfig( Save )
	self.Config = {
		Slots = 2,
		Password = ""
	}

	if Save then
		local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

		if not Success then
			Notify( "Error writing reservedslots config file: "..Err )	

			return	
		end

		Notify( "Shine reservedslots config file created." )
	end
end

function Plugin:SaveConfig()
	local Success, Err = Shine.SaveJSONFile( self.Config, Shine.Config.ExtensionDir..self.ConfigName )

	if not Success then
		Notify( "Error writing reservedslots config file: "..Err )	

		return	
	end

	Notify( "Shine reservedslots config file updated." )
end

function Plugin:LoadConfig()
	local PluginConfig = Shine.LoadJSONFile( Shine.Config.ExtensionDir..self.ConfigName )

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig
end

function Plugin:LockServer( Unlock )
	if Unlock then
		Server.SetPassword( "" )
	else
		Server.SetPassword( self.Config.Password )
	end
end

function Plugin:ClientConnect( Client )
	local Max = Server.GetMaxPlayers()

	local Slots = self.Config.Slots
	local Connected = TableCount( Shine.GameIDs )

	if Max - Slots == Connected then
		Shine:LogString( StringFormat( "[Reserved Slots] Locking the server at %i/%i players.", Connected, Max ) )
		self:LockServer()
	end
end

function Plugin:ClientDisconnect( Client )
	local Max = Server.GetMaxPlayers()

	local Slots = self.Config.Slots
	local Connected = TableCount( Shine.GameIDs )

	if Max - Slots > Connected then
		Shine:LogString( StringFormat( "[Reserved Slots] Unlocking the server at %i/%i players.", Connected, Max ) )
		self:LockServer( true )
	end
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "reservedslots", Plugin )
