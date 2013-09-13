--[[
	Reserved slots.

	The huzzah UWE gave us a proper connection event edition.
]]

local Shine = Shine

local Floor = math.floor
local Max = math.max
local tonumber = tonumber

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ReservedSlots.json"

Plugin.DefaultConfig = {
	Slots = 2, --How many slots?
	TakeSlotInstantly = true --Should a player with reserved access use up a slot straight away?
}

Plugin.CheckConfig = true

function Plugin:Initialise()
	self.Config.Slots = Floor( tonumber( self.Config.Slots ) or 0 )

	if self.Config.Slots > 0 and not self.Config.TakeSlotInstantly then
		self.OldTag = "R_S"..self.Config.Slots

		Server.AddTag( self.OldTag )
	end

	self.Enabled = true

	return true
end

--[[
	Update the server tag with the current reserved slot count.
]]
function Plugin:UpdateTag( Slots )
	if not self.OldTag then
		local Tag = "R_S"..Slots

		Server.AddTag( Tag )

		self.OldTag = Tag
	else
		local Tag = "R_S"..Slots

		if Tag == self.OldTag then return end

		Server.RemoveTag( self.OldTag )

		Server.AddTag( Tag )

		self.OldTag = Tag
	end
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
		local Reserved, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )

		Slots = Max( Slots - Count, 0 )

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
