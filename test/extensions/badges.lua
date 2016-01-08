--[[
	Badges plugin unit test.
]]

local UnitTest = Shine.UnitTest
local Badges = UnitTest:LoadExtension( "badges" )
if not Badges then return end

local TableInsertUnique = table.InsertUnique

local Assigned = {}
local OldGiveBadge = GiveBadge

function GiveBadge( ID, Badge, Row )
	Row = Row or Badges.DefaultRow

	local BadgeRows = Assigned[ ID ]
	if not BadgeRows then
		BadgeRows = {}
		Assigned[ ID ] = BadgeRows
	end

	BadgeRows[ Row ] = BadgeRows[ Row ] or {}
	TableInsertUnique( BadgeRows[ Row ], Badge )

	return true
end

UnitTest:Test( "GetMasterBadgeLookup", function( Assert )
	local MasterBadgeTable
	Assert:Nil( Badges:GetMasterBadgeLookup( MasterBadgeTable ) )

	MasterBadgeTable = {
		[ "1" ] = {
			"test1"
		},
		[ "2" ] = {
			"test2", "test2b"
		},
		[ "8" ] = {
			"test8", "test1"
		}
	}

	local Lookup = Badges:GetMasterBadgeLookup( MasterBadgeTable )
	Assert:NotNil( Lookup )
	Assert:ArrayEquals( { 1, 8 }, Lookup:Get( "test1" ) )
	Assert:ArrayEquals( { 2 }, Lookup:Get( "test2" ) )
	Assert:ArrayEquals( { 2 }, Lookup:Get( "test2b" ) )
	Assert:ArrayEquals( { 8 }, Lookup:Get( "test8" ) )
end )

UnitTest:Test( "MapBadgesToRows", function( Assert )
	local BadgeList = { "test1", "test2", "test2b", "test8" }
	local Lookup = Shine.Multimap{
		test1 = { 1, 8 }, test2 = { 2 }, test2b = { 2 }, test8 = { 8 }
	}

	local Rows = Badges:MapBadgesToRows( BadgeList, Lookup )
	Assert:NotNil( Rows )

	Assert:NotNil( Rows[ 1 ] )
	Assert:NotNil( Rows[ 2 ] )
	Assert:NotNil( Rows[ 8 ] )

	Assert:ArrayEquals( { "test1" }, Rows[ 1 ] )
	Assert:ArrayEquals( { "test2", "test2b" }, Rows[ 2 ] )
	Assert:ArrayEquals( { "test1", "test8" }, Rows[ 8 ] )
end )

UnitTest:Test( "AssignBadgesToID", function( Assert )
	local ID = 123456

	-- No master table, one entry.
	Badges:AssignBadgesToID( ID, {
		Badge = "cake"
	} )

	Assert:NotNil( Assigned[ ID ] )
	Assert:NotNil( Assigned[ ID ][ Badges.DefaultRow ] )
	Assert:Contains( Assigned[ ID ][ Badges.DefaultRow ], "cake" )

	local MasterTable = Shine.Multimap{
		test1 = { 1 },
		test2 = { 2 },
		test3 = { 3 }
	}

	-- Master table, one entry.
	Badges:AssignBadgesToID( ID, {
		Badge = "test1"
	}, MasterTable )

	Assert:NotNil( Assigned[ ID ][ 1 ] )
	Assert:Contains( Assigned[ ID ][ 1 ], "test1" )

	-- Master table, multiple entries.
	Badges:AssignBadgesToID( ID, {
		Badges = { "test2", "test3" }
	}, MasterTable )

	Assert:NotNil( Assigned[ ID ][ 2 ] )
	Assert:NotNil( Assigned[ ID ][ 3 ] )
	Assert:Contains( Assigned[ ID ][ 2 ], "test2" )
	Assert:Contains( Assigned[ ID ][ 3 ], "test3" )

	-- No master table, multiple entries.
	Badges:AssignBadgesToID( ID, {
		Badges = { "morecake", "somuchcake" }
	} )
	Assert:Contains( Assigned[ ID ][ Badges.DefaultRow ], "morecake" )
	Assert:Contains( Assigned[ ID ][ Badges.DefaultRow ], "somuchcake" )

	-- No master table, row based entry.
	Badges:AssignBadgesToID( ID, {
		Badges = {
			[ "1" ] = { "ranoutofcake" },
			[ "8" ] = { "ohwell" }
		}
	} )
	Assert:Contains( Assigned[ ID ][ 1 ], "ranoutofcake" )
	Assert:NotNil( Assigned[ ID ][ 8 ] )
	Assert:Contains( Assigned[ ID ][ 8 ], "ohwell" )
end, function()
	Assigned = {}
end )

UnitTest:Test( "AssignGroupBadge", function( Assert )
	local ID = 123456
	local Group = {
		Badges = { "cake", "morecake", "somuchcake" }
	}

	Badges:AssignGroupBadge( ID, "Test", Group )

	-- Should assign all given badges, and the group name.
	Assert:NotNil( Assigned[ ID ] )
	Assert:NotNil( Assigned[ ID ][ Badges.DefaultRow ] )
	Assert:ArrayEquals( { "cake", "morecake", "somuchcake", "test" },
		Assigned[ ID ][ Badges.DefaultRow ] )
end )

GiveBadge = OldGiveBadge
