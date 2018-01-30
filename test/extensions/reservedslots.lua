--[[
	Reserved slots plugin unit tests.
]]

local UnitTest = Shine.UnitTest

local Plugin = UnitTest:LoadExtension( "reservedslots" )
if not Plugin then return end

local MockPlugin = UnitTest.MockOf( Plugin )

MockPlugin.Config.TakeSlotInstantly = false
MockPlugin.Config.Slots = 2
MockPlugin.Config.SlotType = MockPlugin.SlotType.PLAYABLE

local REAL_SLOT_COUNT = 2
MockPlugin.SetReservedSlotCount = function( self, NumSlots ) REAL_SLOT_COUNT = NumSlots end

local MAX_PLAYERS = 10
local PLAYER_COUNT = 1
local HAS_RESERVED_ACCESS = false
local OCCUPIED_RESERVED_SLOTS = 0

MockPlugin.HasReservedSlotAccess = function() return HAS_RESERVED_ACCESS end
MockPlugin.GetMaxPlayers = function() return MAX_PLAYERS end
MockPlugin.GetRealPlayerCount = function() return PLAYER_COUNT end
MockPlugin.GetNumOccupiedReservedSlots = function() return OCCUPIED_RESERVED_SLOTS end

UnitTest:Test( "CheckConnectionAllowed - Free public slots allows always", function( Assert )
	-- 10 max, 1 connected, allowed regardless of reserved slot access.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

PLAYER_COUNT = 8
UnitTest:Test( "CheckConnectionAllowed - No free public slots and no access abstains", function( Assert )
	-- 10 max, 8 connected, 2 reserved slots, so do not allow (let NS2 decide).
	Assert:Nil( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

HAS_RESERVED_ACCESS = true
UnitTest:Test( "CheckConnectionAllowed - No free public slots allows with access and not full", function( Assert )
	-- 10 max, 8 connected, 2 reserved slots, has reserved slot access, so allow.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

PLAYER_COUNT = MAX_PLAYERS
UnitTest:Test( "CheckConnectionAllowed - Full server abstains even with access", function( Assert )
	-- 10 max, 10 connected, 2 reserved slots, has reserved slot access, so do not allow as the server is full
	-- (let NS2 decide/handle spectator slots)
	Assert:Nil( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 2, REAL_SLOT_COUNT )
end )

OCCUPIED_RESERVED_SLOTS = 1
PLAYER_COUNT = 8
HAS_RESERVED_ACCESS = false
MockPlugin.Config.TakeSlotInstantly = true

UnitTest:Test( "CheckConnectionAllowed - Updates slot count with TakeSlotInstantly", function( Assert )
	-- 10 max, 8 connected.
	-- Should allow, as the slots will update to just 1 free slot (from GetFreeReservedSlots)
	-- and thus the public slot count is 9.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 1, REAL_SLOT_COUNT )
end )

MockPlugin.Config.SlotType = MockPlugin.SlotType.ALL
REAL_SLOT_COUNT = 0
OCCUPIED_RESERVED_SLOTS = 0

HAS_RESERVED_ACCESS = false

local CLIENT_COUNT = 1
local MAX_SPECTATORS = 10
MockPlugin.GetRealClientCount = function() return CLIENT_COUNT end
MockPlugin.GetMaxSpectatorSlots = function() return MAX_SPECTATORS end

PLAYER_COUNT = 1
UnitTest:Test( "CheckConnectionAllowed - ALL: Free public slot allows", function( Assert )
	-- 10 max, 1 connected, allowed regardless of reserved slot access.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 0, REAL_SLOT_COUNT )
end )

PLAYER_COUNT = 10
CLIENT_COUNT = 10
UnitTest:Test( "CheckConnectionAllowed - ALL: Free spectator slot allows", function( Assert )
	-- 10/10 players, 10 max spectators, 0 spectators, 0 occupied slots
	-- Should fall through to assign to a spectator slot.
	Assert:Nil( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 0, REAL_SLOT_COUNT )
end )

CLIENT_COUNT = 18
UnitTest:Test( "CheckConnectionAllowed - ALL: No free unreserved spectator slots denies", function( Assert )
	-- 10/10 players, 8/10 spectators, only reserved slots remaining.
	-- Should deny as no public slots are left.
	Assert:False( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 0, REAL_SLOT_COUNT )
end )

HAS_RESERVED_ACCESS = true
UnitTest:Test( "CheckConnectionAllowed - ALL: No free unreserved spectator slots allows with access", function( Assert )
	-- 10/10 players, 8/10 spectators, only reserved slots remaining but has access.
	-- Should fall through to assign to a spectator slot.
	Assert:Nil( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 0, REAL_SLOT_COUNT )
end )

CLIENT_COUNT = 20
UnitTest:Test( "CheckConnectionAllowed - ALL: No free slots at all denies", function( Assert )
	-- 10/10 players, 10/10 spectators, no slots remaining.
	-- Should deny as no slots are left.
	Assert:False( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 0, REAL_SLOT_COUNT )
end )

OCCUPIED_RESERVED_SLOTS = 1
CLIENT_COUNT = 18
HAS_RESERVED_ACCESS = false

UnitTest:Test( "CheckConnectionAllowed - ALL: Updates slot count with TakeSlotInstantly", function( Assert )
	-- 10 max spectators, 8 connected.
	-- Should fall through, as one of the reserved spectator slots is counted as occupied already
	-- and thus the public spectator slot count is 9.
	Assert:Nil( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 0, REAL_SLOT_COUNT )
end )

MockPlugin.Config.Slots = MAX_SPECTATORS + 2
PLAYER_COUNT = 8
CLIENT_COUNT = 8

UnitTest:Test( "CheckConnectionAllowed - ALL: Updates slot count when reserved includes playable + spectator", function( Assert )
	-- 8/10 players, all spectator slots reserved + 2 playable slots reserved.
	-- 1 player has consumed a reserved slot already, and thus there are in fact
	-- 9 public player slots, so this should be allowed.
	Assert:True( MockPlugin:CheckConnectionAllowed( 1 ) )
	Assert:Equals( 1, REAL_SLOT_COUNT )
end )
