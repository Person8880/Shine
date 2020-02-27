--[[
	Badges plugin unit test.
]]

local UnitTest = Shine.UnitTest
local Badges = UnitTest:LoadExtension( "badges" )
if not Badges then return end

Badges = UnitTest.MockOf( Badges )

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

UnitTest:Before( function()
	Assigned = {}
	Badges:ResetState()
end )

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
	Assert:DeepEquals( Shine.Multimap{
		[ 1 ] = { "test1" },
		[ 2 ] = { "test2", "test2b" },
		[ 8 ] = { "test1", "test8" }
	}, Rows )
end )

local MockGroups = {
	TestGroupWithSingleBadge = {
		Badge = "test1",
		InheritFromDefault = true
	},
	TestGroupWithMultipleBadges = {
		Badges = { "test1", "test2" },
		ForcedBadges = {
			[ "10" ] = "test11"
		}
	},
	TestGroupThatInheritsBadges = {
		InheritsFrom = {
			"TestGroupWithSingleBadge",
			"TestGroupWithMultipleBadges"
		},
		ForcedBadges = {
			[ "3" ] = "test3",
			[ "10" ] = "test10"
		}
	},
	TestGroupWithCycle1 = {
		InheritsFrom = {
			"TestGroupWithCycle2"
		}
	},
	TestGroupWithCycle2 = {
		InheritsFrom = {
			"TestGroupWithCycle1"
		}
	},
	[ -1 ] = {
		Badges = {
			[ "3" ] = { "test3", "test4" },
			[ "10" ] = { "test10", "test11" }
		}
	}
}

function Badges:GetGroupData( GroupName )
	return MockGroups[ GroupName ]
end

local function GroupBadgesForComparison( GroupBadges )
	return {
		Assigned = GroupBadges.Assigned:AsTable(),
		Forced = GroupBadges.Forced and GroupBadges.Forced:AsTable()
	}
end

UnitTest:Test( "BuildGroupBadges - Builds with master badge lookup as expected", function( Assert )
	Badges.MasterBadgeTable = Shine.Multimap{
		test1 = { 5, 6, 7 }
	}

	local GroupBadges = Badges:BuildGroupBadges( "TestGroupThatInheritsBadges" )
	Assert.DeepEquals( "Should have built badges for TestGroupThatInheritsBadges as expected", {
		Assigned = {
			[ 3 ] = { "test3", "test4" },
			[ 5 ] = { "test1", "test2" },
			[ 6 ] = { "test1" },
			[ 7 ] = { "test1" },
			[ 10 ] = { "test10", "test11" }
		},
		Forced = {
			[ 3 ] = "test3",
			[ 10 ] = "test10"
		}
	}, GroupBadgesForComparison( GroupBadges ) )

	GroupBadges = Badges:BuildGroupBadges( "TestGroupWithSingleBadge" )
	Assert.DeepEquals( "Should have built badges for TestGroupWithSingleBadge as expected", {
		Assigned = {
			[ 3 ] = { "test3", "test4" },
			[ 5 ] = { "test1" },
			[ 6 ] = { "test1" },
			[ 7 ] = { "test1" },
			[ 10 ] = { "test10", "test11" }
		}
	}, GroupBadgesForComparison( GroupBadges ) )

	GroupBadges = Badges:BuildGroupBadges( "TestGroupWithMultipleBadges" )
	Assert.DeepEquals( "Should have built badges for TestGroupWithMultipleBadges as expected", {
		Assigned = {
			[ 5 ] = { "test1", "test2" },
			[ 6 ] = { "test1" },
			[ 7 ] = { "test1" }
		},
		Forced = {
			[ 10 ] = "test11"
		}
	}, GroupBadgesForComparison( GroupBadges ) )

	GroupBadges = Badges:BuildGroupBadges( -1 )
	Assert.DeepEquals( "Should have built badges for the default group as expected", {
		Assigned = {
			[ 3 ] = { "test3", "test4" },
			[ 10 ] = { "test10", "test11" }
		}
	}, GroupBadgesForComparison( GroupBadges ) )
end )

UnitTest:Test( "BuildGroupBadges - Builds without master badge lookup as expected", function( Assert )
	Badges.MasterBadgeTable = Shine.Multimap()

	local GroupBadges = Badges:BuildGroupBadges( "TestGroupThatInheritsBadges" )
	Assert.DeepEquals( "Should have built badges for TestGroupThatInheritsBadges as expected", {
		Assigned = {
			[ 3 ] = { "test3", "test4" },
			[ 5 ] = { "test1", "test2" },
			[ 10 ] = { "test10", "test11" }
		},
		Forced = {
			[ 3 ] = "test3",
			[ 10 ] = "test10"
		}
	}, GroupBadgesForComparison( GroupBadges ) )

	GroupBadges = Badges:BuildGroupBadges( "TestGroupWithSingleBadge" )
	Assert.DeepEquals( "Should have built badges for TestGroupWithSingleBadge as expected", {
		Assigned = {
			[ 3 ] = { "test3", "test4" },
			[ 5 ] = { "test1" },
			[ 10 ] = { "test10", "test11" }
		}
	}, GroupBadgesForComparison( GroupBadges ) )

	GroupBadges = Badges:BuildGroupBadges( "TestGroupWithMultipleBadges" )
	Assert.DeepEquals( "Should have built badges for TestGroupWithMultipleBadges as expected", {
		Assigned = {
			[ 5 ] = { "test1", "test2" }
		},
		Forced = {
			[ 10 ] = "test11"
		}
	}, GroupBadgesForComparison( GroupBadges ) )

	GroupBadges = Badges:BuildGroupBadges( -1 )
	Assert.DeepEquals( "Should have built badges for the default group as expected", {
		Assigned = {
			[ 3 ] = { "test3", "test4" },
			[ 10 ] = { "test10", "test11" }
		}
	}, GroupBadgesForComparison( GroupBadges ) )
end )

UnitTest:Test( "BuildGroupBadges - Handles cyclic InheritsFrom list", function( Assert )
	local GroupBadges = Badges:BuildGroupBadges( "TestGroupWithCycle1" )
	Assert.DeepEquals( "Should handle cycle in InheritsFrom list", {
		Assigned = {}
	}, GroupBadgesForComparison( GroupBadges ) )

	GroupBadges = Badges:BuildGroupBadges( "TestGroupWithCycle2" )
	Assert.DeepEquals( "Should handle cycle in InheritsFrom list", {
		Assigned = {}
	}, GroupBadgesForComparison( GroupBadges ) )
end )

UnitTest:Test( "AssignBadgesToID - Assigns badges with no forced badges", function( Assert )
	local ID = 12345

	Badges:AssignBadgesToID( ID, Shine.Multimap{
		{ "test1", "test2" },
		{ "test3", "test4" }
	} )

	Assert.DeepEquals( "Should have assigned the given rows", {
		{ "test1", "test2" },
		{ "test3", "test4" }
	}, Assigned[ ID ] )

	Assert.DeepEquals( "Should not have forced any badges", {}, Badges.ForcedBadges )
end )

UnitTest:Test( "AssignBadgesToID - Assigns badges and forced badges", function( Assert )
	local ID = 12345

	Badges:AssignBadgesToID( ID, Shine.Multimap{
		{ "test1", "test2" },
		{ "test3", "test4" }
	}, Shine.Map( {
		"test1",
		"test3"
	} ) )

	Assert.DeepEquals( "Should have assigned the given rows", {
		{ "test1", "test2" },
		{ "test3", "test4" }
	}, Assigned[ ID ] )

	Assert.DeepEquals( "Should have forced the given badges", {
		"test1",
		"test3"
	}, Badges.ForcedBadges[ ID ] )
end )

GiveBadge = OldGiveBadge
