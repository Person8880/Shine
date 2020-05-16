--[[
	Reserved slots.

	The huzzah UWE gave us a proper connection event edition.
]]

local Shine = Shine

local Floor = math.floor
local GetNumClientsTotal = Server.GetNumClientsTotal
local GetNumPlayersTotal = Server.GetNumPlayersTotal
local GetMaxPlayers = Server.GetMaxPlayers
local GetMaxSpectators = Server.GetMaxSpectators
local Max = math.max
local Min = math.min
local tonumber = tonumber

local Plugin = Shine.Plugin( ... )
Plugin.Version = "2.2"

Plugin.HasConfig = true
Plugin.ConfigName = "ReservedSlots.json"

Plugin.SlotType = table.AsEnum{
	"PLAYABLE", "ALL"
}

Plugin.DefaultConfig = {
	-- How many slots?
	Slots = 2,
	-- Should a player with reserved access use up a slot straight away?
	TakeSlotInstantly = true,
	-- Which type(s) of slot should be reserved?
	SlotType = Plugin.SlotType.PLAYABLE
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "SlotType",
		Validator.InEnum( Plugin.SlotType, Plugin.SlotType.PLAYABLE ) )
	Plugin.ConfigValidator = Validator
end

function Plugin:Initialise()
	self.Config.Slots = Max( Floor( tonumber( self.Config.Slots ) or 0 ), 0 )
	self:SetReservedSlotCount( self:GetFreeReservedSlots() )

	self:CreateCommands()
	self.Enabled = true

	return true
end

function Plugin:OnFirstThink()
	self:SetReservedSlotCount( self:GetFreeReservedSlots() )
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

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam )
	if OldTeam == kSpectatorIndex or NewTeam == kSpectatorIndex then
		-- Update reserved slot count whenever spectators are added or removed.
		self:SetReservedSlotCount( self:GetFreeReservedSlots() )
	end
end

do
	local function IsSpectator( Client ) return Client:GetIsSpectator() end

	function Plugin:GetNumOccupiedReservedSlots()
		local Clients, Count = Shine:GetClientsWithAccess( "sh_reservedslot" )
		if self.Config.SlotType == self.SlotType.ALL then
			-- When reserving all slots, the slot type a
			-- reserved player is in doesn't matter.
			return Count
		end

		local NumInSpectate = Shine.Stream( Clients )
			:Filter( IsSpectator )
			:GetCount()
		-- For reserved player slots, only count those not in spectator slots.
		return Count - Min( NumInSpectate, self:GetMaxSpectatorSlots() )
	end
end

function Plugin:GetFreeReservedSlots()
	-- If considering all slots, then the reserved slot count is offset by the
	-- number of spectator slots to produce the number of reserved playable slots.
	local Offset = self.Config.SlotType == self.SlotType.ALL
		and self:GetMaxSpectatorSlots() or 0

	local Slots = self.Config.Slots
	if not self.Config.TakeSlotInstantly then
		return Max( Slots - Offset, 0 )
	end

	local Count = self:GetNumOccupiedReservedSlots()
	return Max( Slots - Count - Offset, 0 )
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

function Plugin:GetRealClientCount()
	return GetNumClientsTotal() - 1
end

function Plugin:GetMaxPlayers()
	return GetMaxPlayers()
end

function Plugin:GetMaxSpectatorSlots()
	return GetMaxSpectators()
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

	if self:HasReservedSlotAccess( Client ) then
		self:SetReservedSlotCount( self:GetFreeReservedSlots() )
	end
end

Plugin.ConnectionHandlers = {
	-- Consumes playable slots only. Spectator slots are handled entirely by the default handler.
	[ Plugin.SlotType.PLAYABLE ] = function( self, ID )
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
	end,
	-- Consumes all slots, spectator slots will be blocked if they are reserved.
	[ Plugin.SlotType.ALL ] = function( self, ID )
		local NumClients = self:GetRealClientCount()
		local MaxClients = self:GetMaxPlayers() + self:GetMaxSpectatorSlots()

		local Slots = self.Config.Slots

		-- Deduct reserved slot users from the number of reserved slots empty.
		if self.Config.TakeSlotInstantly then
			self:SetReservedSlotCount( self:GetFreeReservedSlots() )
			-- The reserved slot count only applies to playable slots, this includes
			-- spectator slots.
			Slots = Max( Slots - self:GetNumOccupiedReservedSlots(), 0 )
		end

		-- If only spectator slots are free, then the default handler needs to run
		-- to assign them to a spectator slot properly.
		local ALLOWED
		local ShouldFallThrough = self:GetRealPlayerCount() >= self:GetMaxPlayers()
		if not ShouldFallThrough then
			ALLOWED = true
		end

		-- Allow if all slots have not yet been filled.
		if NumClients < MaxClients - Slots then
			return ALLOWED
		end

		-- Allow if they have reserved access and we're not full.
		local HasSlots = NumClients < MaxClients
		if HasSlots and self:HasReservedSlotAccess( ID ) then
			return ALLOWED
		end

		-- Deny entirely if the server is completely full or they have no
		-- reserved slot access and only reserved slots are left.
		return false, HasSlots and "Slot is reserved." or "Server is currently full."
	end
}

--[[
	Checks the given NS2ID to see if it has reserved slot access.

	If they do, or if the server has enough free non-reserved slots, they are allowed in.
	If the client will be assigned to a spectator slot, then this will defer to the default
	handler.
]]
function Plugin:CheckConnectionAllowed( ID )
	return self.ConnectionHandlers[ self.Config.SlotType ]( self, tonumber( ID ) )
end

return Plugin
