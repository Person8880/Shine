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
		self:UpdateTag( self:GetFreeReservedSlots() )
	end

	self:CreateCommands()
	self.Enabled = true

	return true
end

function Plugin:CreateCommands()
	local function SetSlotCount( Client, Slots )
		self.Config.Slots = Slots

		self:UpdateTag( self:GetFreeReservedSlots() )
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

function Plugin:RemoveRSTag()
	local Tags = {}

	Server.GetTags( Tags )

	for i = 1, #Tags do
		local Tag = Tags[ i ]

		if Tag and Tag:find( "R_S" ) then
			Server.RemoveTag( Tag )
		end
	end
end

--[[
	Update the server tag with the current reserved slot count.
]]
function Plugin:UpdateTag( Slots )
	self:RemoveRSTag()
	Server.AddTag( "R_S"..Slots )
end

function Plugin:GetRealPlayerCount()
	--This includes the connecting player for whatever reason...
	return GetNumPlayersTotal() - 1
end

function Plugin:ClientConnect( Client )
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
	local MaxPlayers = GetMaxPlayers()

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
		return true
	end

	if Slots == 0 then
		return true
	end

	local MaxPublic = MaxPlayers - Slots

	--We've got enough room for them.
	if MaxPublic > Connected then
		return true
	end

	return false
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )
	self:RemoveRSTag()
end

Shine:RegisterExtension( "reservedslots", Plugin )
