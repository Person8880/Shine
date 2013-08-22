--[[
	Reserved slots.

	The hurry up and give us proper connection control UWE edition.
]]

local Shine = Shine
local Timer = Shine.Timer

local Clamp = math.Clamp
local Floor = math.floor
local Max = math.max
local Notify = Shared.Message
local StringFormat = string.format
local TableCount = table.Count
local TableRandom = table.ChooseRandom

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ReservedSlots.json"

Plugin.MODE_PASSWORD = 1
Plugin.MODE_REDIRECT = 2
Plugin.MODE_PASSWORD_ENFORCED = 3

Plugin.DefaultConfig = {
	Slots = 2,
	Password = "",
	Mode = 1,
	Redirect = { 
		{ IP = "127.0.0.1", Port = "27015", Password = "", ReservedSlots = 0 }
	}
}

Plugin.CheckConfig = true

function Plugin:Initialise()
	self.Config.Mode = Clamp( Floor( self.Config.Mode ), 1, 3 )

	self.Enabled = true

	return true
end

function Plugin:LockServer( Unlock )
	self.Locked = not Unlock

	Server.SetPassword( Unlock and "" or self.Config.Password )
end

--[[
	Sends a client to the server specified by the ServerData table.
]]
function Plugin:RedirectClient( Client, ServerData )
	local IP = ServerData.IP
	local Port = ServerData.Port
	local Password = ""

	if ServerData.Password and #ServerData.Password > 0 then
		Password = ServerData.Password
	end

	local Player = Client:GetControllingPlayer()

	if Player then
		local Name = Player:GetName()
		local ID = Client:GetUserId()

		Shine:LogString( StringFormat( "[Reserved Slots] Redirected client %s[%s] to server: %s:%s.", Name, ID, IP, Port ) )
	end

	Server.SendNetworkMessage( Client, "Shine_Command", { 
		Command = StringFormat( "connect %s:%s%s", IP, Port, Password )
	}, true )
end

--[[
	Checks all set redirect servers for players, and redirects the player to one with free slots,
	taking reserved slots into account.

	Note: THIS METHOD IS NOT PERFECT! The information may be slighlty out of date, and a server could fill
	when we redirect, but it's better than doing nothing.

	inb4 UWE forums complaining about it saying it's finding a server with room then sending them to one without room.

	I can't make it any better than this, information is delayed and I can't know about other players in the world
	suddenly connecting.
]]
function Plugin:CheckRedirects( Client )
	local ID = Client:GetUserId()
	local Redirects = self.Config.Redirect

	local DataTable = {}

	--Gives us 5 seconds to get the server data, as close as possible while leaving room for the HTTP request to be processed.
	Timer.Simple( 20, function()
		local Client = Shine.GetClientByNS2ID( ID )
		if not Client then return end
		
		for i = 1, #Redirects do
			local Redirect = Redirects[ i ]

			local Reserved = Redirect.ReservedSlots or 0

			Shine.QueryServerPopulation( Redirect.IP, tonumber( Redirect.Port ) + 1, function( Connected, Max )
				if not Connected or not Max then return end
				
				DataTable[ #DataTable + 1 ] = {
					IP = Redirect.IP,
					Port = Redirect.Port,
					Password = Redirect.Password,
					Max = Max - Reserved,
					Connected = Connected
				}
			end )
		end
	end )

	--5 seconds later, we gather our results and redirect or kick.
	Timer.Simple( 25, function()
		local Client = Shine.GetClientByNS2ID( ID )
		if not Client then return end

		--We never got any useful data back, so just guess and send them to a random server.
		if #DataTable == 0 then
			local Server = TableRandom( Redirects )

			self:RedirectClient( Client, Server )

			return
		end

		local BestServer
		local BestSlots = 9001

		--Find the server with the fewest open slots, as it's got the most players.
		for Index, Data in pairs( DataTable ) do
			local SlotsFree = Data.Max - Data.Connected

			if SlotsFree > 0 then
				if SlotsFree < BestSlots then
					BestSlots = SlotsFree
					BestServer = Data
				end
			end
		end

		--This is a risky join, we may not get in.
		if BestSlots < 3 then
			--Try and find a server that's got more slots, but not so much that it's empty.
			for Index, Data in pairs( DataTable ) do
				local SlotsFree = Data.Max - Data.Connected

				if SlotsFree > BestSlots and SlotsFree < Data.Max * 0.5 then
					BestServer = Data
					break
				end
			end
		end

		--We found a server with room, now hope that you connect and it's not empty!
		if BestServer then
			self:RedirectClient( Client, BestServer )

			return
		end

		Shine:NotifyColour( Client, 255, 50, 0, "No servers with free slots were found." )

		--Sorry, but reserved slots are reserved.
		Timer.Simple( 5, function()
			local Client = Shine.GetClientByNS2ID( ID )
			if not Client then return end
			
			Server.DisconnectClient( Client )
		end )
	end )
end

local OnReservedConnect = {
	function( self, Client, Connected, MaxPlayers, MaxPublic )
		if Connected == MaxPublic then
			Shine:LogString( StringFormat( "[Reserved Slots] Locking the server at %i/%i players.", Connected, MaxPlayers ) )
		end

		self:LockServer()
	end,

	function( self, Client, Connected, MaxPlayers, MaxPublic )
		if Connected == MaxPublic then return end
		if Shine:HasAccess( Client, "sh_reservedslot" ) then return end
		
		local Redirect = self.Config.Redirect

		Client.Redirecting = true

		if Redirect[ 1 ] then
			self:CheckRedirects( Client )

			return
		end

		Shine:NotifyColour( Client, 255, 255, 0, "This server is full, you will be redirected to one of our other servers." )

		Timer.Simple( 20, function()
			if Shine:IsValidClient( Client ) then
				self:RedirectClient( Client, Redirect )
			end
		end )
	end,

	function( self, Client, Connected, MaxPlayers, MaxPublic )
		if Connected == MaxPublic then
			Shine:LogString( StringFormat( "[Reserved Slots] Locking the server at %i/%i players.", Connected, MaxPlayers ) )
		end

		self:LockServer()

		if Connected <= MaxPublic then return end
		if Shine:HasAccess( Client, "sh_reservedslot" ) then return end

		Client.Kicking = true

		--Enforce the slots, kick out anyone without the proper access that got in somehow.
		Timer.Simple( 15, function()
			if not Shine:IsValidClient( Client ) then return end
			
			Server.DisconnectClient( Client )
		end )
	end
}

local OnReservedDisconnect = {
	function( self, Client, Connected, MaxPlayers, MaxPublic )
		if Connected == ( MaxPublic - 1 ) then
			Shine:LogString( StringFormat( "[Reserved Slots] Unlocking the server at %i/%i players.", Connected, MaxPlayers ) )
		end

		self:LockServer( true )
	end,

	function( self, Client )
		--Do nothing...
	end,

	function( self, Client, Connected, MaxPlayers, MaxPublic )
		if Connected == ( MaxPublic - 1 ) then
			Shine:LogString( StringFormat( "[Reserved Slots] Unlocking the server at %i/%i players.", Connected, MaxPlayers ) )
		end

		self:LockServer( true )
	end
}

--[[
	Ensure the relevant messages are displayed to the client.
]]
function Plugin:ClientConfirmConnect( Client )
	local Mode = self.Config.Mode

	if Mode == self.MODE_REDIRECT then
		if not Client.Redirecting then return end

		Shine:NotifyColour( Client, 255, 255, 0, "This server is full, checking our other servers for slots." )
		Shine:NotifyColour( Client, 255, 255, 0, "You will be redirected if a server with slots is found." )
	elseif Mode == self.MODE_PASSWORD_ENFORCED then
		if not Client.Kicking then return end
		
		Shine:NotifyColour( Client, 255, 50, 0, "The slot you have joined is reserved." )
	end
end

function Plugin:ClientConnect( Client )
	local MaxPlayers = Server.GetMaxPlayers()

	local ConnectedAdmins, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	local Slots = Max( self.Config.Slots - Count, 0 )

	if Slots == 0 then return end

	local Connected = TableCount( Shine.GameIDs )

	local MaxPublic = MaxPlayers - Slots

	if MaxPublic <= Connected then
		OnReservedConnect[ self.Config.Mode ]( self, Client, Connected, MaxPlayers, MaxPublic )
	end
end

function Plugin:ClientDisconnect( Client )
	local MaxPlayers = Server.GetMaxPlayers()

	local ConnectedAdmins, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	local Slots = Max( self.Config.Slots - Count, 0 )
	local Connected = TableCount( Shine.GameIDs )

	local MaxPublic = MaxPlayers - Slots

	if MaxPublic > Connected then
		OnReservedDisconnect[ self.Config.Mode ]( self, Client, Connected, MaxPlayers, MaxPublic )
	end
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "reservedslots", Plugin )
