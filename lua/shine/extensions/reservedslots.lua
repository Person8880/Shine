--[[
	Reserved slots.

	Currently only the crude password method. I'll expand it if UWE ever get a proper connection event.
]]

local Shine = Shine

local Max = math.max
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
	self.Locked = not Unlock

	Server.SetPassword( Unlock and "" or self.Config.Password )
end

function Plugin:ClientConnect( Client )
	local MaxPlayers = Server.GetMaxPlayers()

	local ConnectedAdmins, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	local Slots = Max( self.Config.Slots - Count, 0 )

	if Slots == 0 then return end

	local Connected = TableCount( Shine.GameIDs )

	if MaxPlayers - Slots == Connected and not self.Locked then
		Shine:LogString( StringFormat( "[Reserved Slots] Locking the server at %i/%i players.", Connected, MaxPlayers ) )
		self:LockServer()
	end
end

function Plugin:ClientDisconnect( Client )
	local MaxPlayers = Server.GetMaxPlayers()

	local ConnectedAdmins, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	local Slots = Max( self.Config.Slots - Count, 0 )
	local Connected = TableCount( Shine.GameIDs )

	if MaxPlayers - Slots > Connected and self.Locked then
		Shine:LogString( StringFormat( "[Reserved Slots] Unlocking the server at %i/%i players.", Connected, MaxPlayers ) )
		self:LockServer( true )
	end
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "reservedslots", Plugin )
