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
	Slots = 2, --How many slots?
	TakeSlotInstantly = true --Should a player with reserved access use up a slot straight away?
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	self.Config.Slots = Floor( tonumber( self.Config.Slots ) or 0 )

	if self.Config.Slots > 0 then
		self:UpdateSlots( self:GetFreeReservedSlots() )
	end

	self:CreateCommands()
	self.Enabled = true

	return true
end

function Plugin:OnFirstThink()
	if self.Config.Slots > 0 then
		self:UpdateSlots( self:GetFreeReservedSlots() )
	end
end

function Plugin:CreateCommands()
	local function SetSlotCount( Client, Slots )
		self.Config.Slots = Slots

		self:UpdateSlots( self:GetFreeReservedSlots() )
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

	local Reserved, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

	Slots = Max( Slots - Count, 0 )

	return Slots
end

--[[
	Updates the the current reserved slot count.
]]
function Plugin:UpdateSlots( Slots )
	Server.SetReservedSlotLimit(Slots)
end

function Plugin:GetRealPlayerCount()
	--GetNumPlayersTotal returns the number of client connections (including the connecting client)
	return GetNumPlayersTotal() - 1
end

function Plugin:ClientConnect( Client )
	self:UpdateSlots( self:GetFreeReservedSlots() )
end

function Plugin:HasReservedSlotAccess( Client )
	return Shine:HasAccess( Client, "sh_reservedslot" )
end

--[[
	Update the server tag if a reserved slot client disconnects.
]]
function Plugin:ClientDisconnect( Client )
	if not self.Config.TakeSlotInstantly then return end

	if self.Config.Slots > 0 and self:HasReservedSlotAccess( Client ) then
		self:UpdateSlots( self:GetFreeReservedSlots() )
	end
end

--[[
	A simple and effective reserved slot system.
	At last, a proper connection event.
]]
function Plugin:CheckConnectionAllowed( ID )
	ID = tonumber( ID )

	local NumPlayers = self:GetRealPlayerCount()
	local MaxPlayers = GetMaxPlayers()

	local Slots = self.Config.Slots

	--Deduct reserved slot users from the number of reserved slots empty.
	if self.Config.TakeSlotInstantly then
		Slots = self:GetFreeReservedSlots()

		self:UpdateSlots( Slots )
	end

	--Check for available public slots
	if NumPlayers < MaxPlayers - Slots then
		return true
	end

	--Allow if they have reserved access
	if NumPlayers < MaxPlayers and self:HasReservedSlotAccess( ID ) then
		return true
	end
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )
	self:RemoveRSTag()
end

Shine:RegisterExtension( "reservedslots", Plugin )
