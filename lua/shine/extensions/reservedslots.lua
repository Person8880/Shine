--[[
	Reserved slots.

	The huzzah UWE gave us a proper connection event edition.
]]

local Shine = Shine

local Floor = math.floor
local GetNumPlayersTotal = Server.GetNumPlayersTotal
local GetMaxPlayers = Server.GetMaxPlayers
local Max = math.max
local tonumber = tonumber

local Plugin = {}
Plugin.Version = "2.1"

Plugin.HasConfig = true
Plugin.ConfigName = "ReservedSlots.json"

Plugin.DefaultConfig = {
	-- How many slots?
	Slots = 2,
	-- Should a player with reserved access use up a slot straight away?
	TakeSlotInstantly = true
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Config.Slots = Max( Floor( tonumber( self.Config.Slots ) or 0 ), 0 )

	if self.Config.Slots > 0 then
		self:SetReservedSlotCount( self:GetFreeReservedSlots() )
	end

	self:CreateCommands()
	self.Enabled = true

	return true
end

function Plugin:CreateCommands()
	local function SetSlotCount( Client, Slots )
		self.Config.Slots = Slots
		self:SetReservedSlotCount( self:GetFreeReservedSlots() )
		self:SaveConfig()
		Shine:AdminPrint( Client, "%s set reserved slot count to %i", true,
			Shine.GetClientInfo( Client ), Slots )
	end
	local SetSlotCommand = self:BindCommand( "sh_setresslots", "resslots", SetSlotCount )
	SetSlotCommand:AddParam{ Type = "number", Min = 0, Round = true,
		Error = "Please specify the number of slots to set.", Help = "slots" }
	SetSlotCommand:Help( "Sets the number of reserved slots." )
end

function Plugin:GetFreeReservedSlots()
	local Slots = self.Config.Slots
	if not self.Config.TakeSlotInstantly then
		return Slots
	end

	local _, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )
	return Max( Slots - Count, 0 )
end

--[[
	Set the number of reserved slots for the server browser/NS2 code.
]]
function Plugin:SetReservedSlotCount( NumSlots )
	Server.SetReservedSlotLimit( NumSlots )
end

function Plugin:GetRealPlayerCount()
	-- This includes the connecting player for whatever reason...
	return GetNumPlayersTotal() - 1
end

function Plugin:GetMaxPlayers()
	return GetMaxPlayers()
end

function Plugin:HasReservedSlotAccess( Client )
	return Shine:HasAccess( Client, "sh_reservedslot" )
end

function Plugin:ClientConnect( Client )
	self:SetReservedSlotCount( self:GetFreeReservedSlots() )
end

--[[
	Update the number of free slots if a client who had reserved slot access
	disconnects, and we take slots instantly.
]]
function Plugin:ClientDisconnect( Client )
	if not self.Config.TakeSlotInstantly then return end

	if self.Config.Slots > 0 and self:HasReservedSlotAccess( Client ) then
		self:SetReservedSlotCount( self:GetFreeReservedSlots() )
	end
end

--[[
	Checks the given NS2ID to see if it has reserved slot access.

	If they do, or if the server has enough free non-reserved slots, they are allowed in.
	Otherwise NS2/another listener decides what happens to them.
]]
function Plugin:CheckConnectionAllowed( ID )
	ID = tonumber( ID )

	local NumPlayers = self:GetRealPlayerCount()
	local MaxPlayers = self:GetMaxPlayers()

	local Slots = self.Config.Slots

	-- Deduct reserved slot users from the number of reserved slots empty.
	if self.Config.TakeSlotInstantly then
		Slots = self:GetFreeReservedSlots()
		self:SetReservedSlotCount( Slots )
	end

	-- Allow if there's less players than public slots.
	if NumPlayers < MaxPlayers - Slots then
		return true
	end

	-- Allow if they have reserved access and we're not full.
	if NumPlayers < MaxPlayers and self:HasReservedSlotAccess( ID ) then
		return true
	end

	-- Here either they have reserved slot access but the server is full,
	-- or they don't have reserved slot access and there's no free public slots.
	-- Thus, fall through to the default NS2 behaviour which handles spectator slots.
end

Shine:RegisterExtension( "reservedslots", Plugin )
