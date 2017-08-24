--[[
	Reserved slots plugin unit tests.
]]

local UnitTest = Shine.UnitTest

local Plugin = UnitTest:LoadExtension( "reservedslots" )
if not Plugin then return end

local MockPlugin = UnitTest.MockOf( Plugin )

MockPlugin.Config.TakeSlotInstantly = false
MockPlugin.Config.Slots = 2

local REAL_SLOT_COUNT = 2
MockPlugin.SetReservedSlotCount = function( self, NumSlots ) REAL_SLOT_COUNT = NumSlots end

local MAX_PLAYERS = 10
local PLAYER_COUNT = 1
local HAS_RESERVED_ACCESS = false

MockPlugin.HasReservedSlotAccess = function() return HAS_RESERVED_ACCESS end
MockPlugin.GetMaxPlayers = function() return MAX_PLAYERS end
MockPlugin.GetRealPlayerCount = function() return PLAYER_COUNT end

UnitTest:Test( "CheckConnectionAllowed - Free public slots allows always", function( Assert )
	-- 10 max, 1 connected, allowed regardless of reserved slot access.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

UnitTest:Test( "CheckConnectionAllowed - No free public slots and no access abstains", function( Assert )
	PLAYER_COUNT = 8
	-- 10 max, 8 connected, 2 reserved slots, so do not allow (let NS2 decide).
	Assert:Nil( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

UnitTest:Test( "CheckConnectionAllowed - No free public slots allows with access and not full", function( Assert )
	HAS_RESERVED_ACCESS = true
	-- 10 max, 8 connected, 2 reserved slots, has reserved slot access, so allow.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

UnitTest:Test( "CheckConnectionAllowed - Full server abstains even with access", function( Assert )
	PLAYER_COUNT = MAX_PLAYERS
	-- 10 max, 10 connected, 2 reserved slots, has reserved slot access, so do not allow as the server is full
	-- (let NS2 decide/handle spectator slots)
	Assert:Nil( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

MockPlugin.GetFreeReservedSlots = function() return 1 end
MockPlugin.Config.TakeSlotInstantly = true

UnitTest:Test( "CheckConnectionAllowed - Updates slot count with TakeSlotInstantly", function( Assert )
	PLAYER_COUNT = 8
	HAS_RESERVED_ACCESS = false

	-- 10 max, 8 connected.
	-- Should allow, as the slots will update to just 1 free slot (from GetFreeReservedSlots)
	-- and thus the public slot count is 9.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 1, REAL_SLOT_COUNT )
end )
