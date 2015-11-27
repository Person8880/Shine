--[[
	Player library tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "EqualiseTeamCounts", function( Assert )
	local TeamMembers = {
		{ 1, 2, 3, 4 },
		{ 5, 6, 7, 8, 9, 10 }
	}

	Shine.EqualiseTeamCounts( TeamMembers )

	Assert:ArrayEquals( { 1, 2, 3, 4, 10 }, TeamMembers[ 1 ] )
	Assert:ArrayEquals( { 5, 6, 7, 8, 9 }, TeamMembers[ 2 ] )

	local TeamMembers = {
		{ 1, 2, 3, 4 },
		{ 5, 6, 7, 8, 9, 10, 11 }
	}

	Shine.EqualiseTeamCounts( TeamMembers )

	Assert:ArrayEquals( { 1, 2, 3, 4, 11 }, TeamMembers[ 1 ] )
	Assert:ArrayEquals( { 5, 6, 7, 8, 9, 10 }, TeamMembers[ 2 ] )

	local TeamMembers = {
		{ 5, 6, 7, 8, 9, 10 },
		{ 1, 2, 3, 4 }
	}

	Shine.EqualiseTeamCounts( TeamMembers )

	Assert:ArrayEquals( { 1, 2, 3, 4, 10 }, TeamMembers[ 2 ] )
	Assert:ArrayEquals( { 5, 6, 7, 8, 9 }, TeamMembers[ 1 ] )

	local TeamMembers = {
		{ 5, 6, 7, 8, 9, 10, 11 },
		{ 1, 2, 3, 4 }
	}

	Shine.EqualiseTeamCounts( TeamMembers )

	Assert:ArrayEquals( { 1, 2, 3, 4, 11 }, TeamMembers[ 2 ] )
	Assert:ArrayEquals( { 5, 6, 7, 8, 9, 10 }, TeamMembers[ 1 ] )
end )
