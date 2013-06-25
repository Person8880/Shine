--[[
	Reserved slots.

	Currently only the crude password method. I'll expand it if UWE ever get a proper connection event.
]]

local Shine = Shine

local Clamp = math.Clamp
local Floor = math.floor
local Max = math.max
local Notify = Shared.Message
local StringFormat = string.format
local TableCount = table.Count

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ReservedSlots.json"

Plugin.MODE_PASSWORD = 1
Plugin.MODE_REDIRECT = 2

Plugin.DefaultConfig = {
	Slots = 2,
	Password = "",
	Mode = 1,
	Redirect = { IP = "127.0.0.1", Port = "27015", Password = "" }
}

Plugin.CheckConfig = true

function Plugin:Initialise()
	self.Config.Mode = Clamp( Floor( self.Config.Mode ), 1, 2 )

	self.Enabled = true

	return true
end

function Plugin:LockServer( Unlock )
	self.Locked = not Unlock

	Server.SetPassword( Unlock and "" or self.Config.Password )
end

local OnReservedConnect = {
	function( self, Client, Connected, MaxPlayers )
		if not self.Locked then
			Shine:LogString( StringFormat( "[Reserved Slots] Locking the server at %i/%i players.", Connected, MaxPlayers ) )
			self:LockServer()
		end
	end,

	function( self, Client )
		local Redirect = self.Config.Redirect

		local IP = Redirect.IP
		local Port = Redirect.Port
		local Password = ""

		if Redirect.Password and #Redirect.Password > 0 then
			Password = " "..Redirect.Password
		end

		Shine:NotifyColour( Client, 255, 255, 0, "This server is full, you will be redirected to one of our other servers." )

		Shine.Timer.Simple( 20, function()
			if Shine:IsValidClient( Client ) then
				Server.SendNetworkMessage( Client, "Shine_Command", { 
					Command = StringFormat( "connect %s:%s%s", IP, Port, Password )
				}, true )
			end
		end )
	end
}

local OnReservedDisconnect = {
	function( self, Client, Connected, MaxPlayers )
		if self.Locked then
			Shine:LogString( StringFormat( "[Reserved Slots] Unlocking the server at %i/%i players.", Connected, MaxPlayers ) )
			self:LockServer( true )
		end
	end,

	function( self, Client )
		--Do nothing...
	end
}

function Plugin:ClientConnect( Client )
	local MaxPlayers = Server.GetMaxPlayers()

	local ConnectedAdmins, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	local Slots = Max( self.Config.Slots - Count, 0 )

	if Slots == 0 then return end

	local Connected = TableCount( Shine.GameIDs )

	if MaxPlayers - Slots <= Connected then
		OnReservedConnect[ self.Config.Mode ]( self, Client, Connected, MaxPlayers )
	end
end

function Plugin:ClientDisconnect( Client )
	local MaxPlayers = Server.GetMaxPlayers()

	local ConnectedAdmins, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	local Slots = Max( self.Config.Slots - Count, 0 )
	local Connected = TableCount( Shine.GameIDs )

	if MaxPlayers - Slots > Connected then
		OnReservedDisconnect[ self.Config.Mode ]( self, Client, Connected, MaxPlayers )
	end
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "reservedslots", Plugin )
