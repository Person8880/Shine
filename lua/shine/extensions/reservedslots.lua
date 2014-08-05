--[[
	Reserved slots.

	The huzzah UWE gave us a proper connection event edition.
]]

local Shine = Shine

local Floor = math.floor
local Max = math.max
local tonumber = tonumber

local Plugin = {}
Plugin.Version = "2.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ReservedSlots.json"

Plugin.DefaultConfig = {
	Slots = 2, --How many slots?
	TakeSlotInstantly = true --Should a player with reserved access use up a slot straight away?
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Config.Slots = Floor( tonumber( self.Config.Slots ) or 0 )

	if self.Config.Slots > 0 then
		if not self.Config.TakeSlotInstantly then
			Server.AddTag( "R_S"..self.Config.Slots )
		else
			Server.AddTag( "R_S"..self:GetFreeReservedSlots() )
		end
	end

	self.ConnectingCount = 0
	self.Connecting = {}

	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:CreateCommands()
	local function SetSlotCount( Client, Slots )
		self.Config.Slots = Slots

		self:UpdateTag( self:GetFreeReservedSlots() )

		self:SaveConfig()
	end
	local SetSlotCommand = self:BindCommand( "sh_setresslots", "resslots", SetSlotCount )
	SetSlotCommand:AddParam{ Type = "number", Min = 0, Round = true, Error = "Please specify the number of slots to set." }
	SetSlotCommand:Help( "<slots> Sets the number of reserved slots." )
end

function Plugin:GetFreeReservedSlots()
	local Slots = self.Config.Slots

	if not self.Config.TakeSlotInstantly then
		return Slots
	end

	local Reserved, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	Slots = Max( Slots - Count, 0 )

	return Slots
end

--[[
	Update the server tag with the current reserved slot count.
]]
function Plugin:UpdateTag( Slots )
	local Tags = {}

	Server.GetTags( Tags )

	for i = 1, #Tags do
		local Tag = Tags[ i ]

		if Tag and Tag:find( "R_S" ) then
			Server.RemoveTag( Tag )
		end
	end

	Server.AddTag( "R_S"..Slots )
end

local GetNumPlayers = Server.GetNumPlayers

--[[
	Returns a better estimate at the player count than Server.GetNumPlayers() alone.
	Takes into account connecting but not loaded players.
]]
function Plugin:GetRealPlayerCount()
	return GetNumPlayers() + self.ConnectingCount
end

--[[
	Adds a player to the connecting list. If they cancel loading we won't
	know, so we give them 5 minutes to connect (NS2 can be slow to load...)
	then remove them if they haven't connected by then.
]]
function Plugin:AddConnectingPlayer( ID )
	--We don't want to add them again if they're still in the list.
	if not self.Connecting[ ID ] then
		self.Connecting[ ID ] = true
		self.ConnectingCount = self.ConnectingCount + 1
	end

	self:CreateTimer( "Connecting_"..ID, 300, 1, function()
		if not self.Connecting[ ID ] then return end
		
		self.Connecting[ ID ] = nil
		self.ConnectingCount = self.ConnectingCount - 1
	end )
end

--[[
	On final connect, if we had the client stored as a connecting client,
	then remove them as Server.GetNumPlayers() will now count them.
]]
function Plugin:ClientConnect( Client )
	local ID = Client:GetUserId()

	if self.Connecting[ ID ] then
		self.Connecting[ ID ] = nil
		self.ConnectingCount = self.ConnectingCount - 1

		self:DestroyTimer( "Connecting_"..ID )
	end

	self:UpdateTag( self:GetFreeReservedSlots() )
end


--[[
	Update the server tag if a reserved slot client disconnects.
]]
function Plugin:ClientDisconnect( Client )
	if not self.Config.TakeSlotInstantly then return end
	
	if self.Config.Slots > 0 and Shine:HasAccess( Client, "sh_reservedslot" ) then
		self:UpdateTag( self:GetFreeReservedSlots() )
	end
end

--[[
	A simple and effective reserved slot system.
	At last, a proper connection event.
]]
function Plugin:CheckConnectionAllowed( ID )
	ID = tonumber( ID )

	local Connected = self:GetRealPlayerCount()
	local MaxPlayers = Server.GetMaxPlayers()

	local Slots = self.Config.Slots

	--Deduct reserved slot users from the number of reserved slots empty.
	if self.Config.TakeSlotInstantly then
		Slots = self:GetFreeReservedSlots()

		self:UpdateTag( Slots )
	end

	--Deny on full.
	if Connected >= MaxPlayers then return false end
	--Allow if they have reserved access, skip checking the connected count.
	if Shine:HasAccess( ID, "sh_reservedslot" ) then
		self:AddConnectingPlayer( ID )

		return true
	end

	if Slots == 0 then
		self:AddConnectingPlayer( ID )

		return true
	end

	local MaxPublic = MaxPlayers - Slots

	--We've got enough room for them.
	if MaxPublic > Connected then
		self:AddConnectingPlayer( ID )

		return true
	end

	return false
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )
	
	self.ConnectingCount = nil
	self.Connecting = nil

	self.Enabled = false
end

Shine:RegisterExtension( "reservedslots", Plugin )
