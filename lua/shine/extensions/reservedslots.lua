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

function Plugin:Initialise()
	self.Config.Slots = Floor( tonumber( self.Config.Slots ) or 0 )

	if self.Config.Slots > 0 then
		if not self.Config.TakeSlotInstantly then
			Server.AddTag( "R_S"..self.Config.Slots )
		else
			Server.AddTag( "R_S"..self:GetFreeReservedSlots() )
		end
	end

	self.Enabled = true

	return true
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

--[[
	A simple and effective reserved slot system.
	At last, a proper connection event.
]]
function Plugin:CheckConnectionAllowed( ID )
	local Connected = Server.GetNumPlayers()
	local MaxPlayers = Server.GetMaxPlayers()

	--Deny on full.
	if Connected >= MaxPlayers then return false end
	--Allow if they have reserved access, skip checking the connected count.
	if Shine:HasAccess( tonumber( ID ), "sh_reservedslot" ) then return true end

	local Slots = self.Config.Slots

	--Deduct reserved slot users from the number of reserved slots empty.
	if self.Config.TakeSlotInstantly then
		Slots = self:GetFreeReservedSlots()

		self:UpdateTag( Slots )
	
		if Slots == 0 then return true end
	end

	local MaxPublic = MaxPlayers - Slots

	--We've got enough room for them.
	if MaxPublic > Connected then return true end

	return false
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "reservedslots", Plugin )
