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

UnitTest:Test( "NS2ToSteamID", function( Assert )
	Assert:Equals( "STEAM_0:0:1000", Shine.NS2ToSteamID( 2000 ) )
	Assert:Equals( "STEAM_0:1:1000", Shine.NS2ToSteamID( 2001 ) )
end )

UnitTest:Test( "NS2ToSteam3ID", function( Assert )
	Assert:Equals( "[U:1:2000]", Shine.NS2ToSteam3ID( 2000 ) )
end )

UnitTest:Test( "SteamIDToNS2", function( Assert )
	Assert:Equals( 2000, Shine.SteamIDToNS2( "STEAM_0:0:1000" ) )
	Assert:Equals( 2001, Shine.SteamIDToNS2( "STEAM_0:1:1000" ) )
	Assert:Equals( 2000, Shine.SteamIDToNS2( "[U:1:2000]" ) )
end )

UnitTest:Test( "NS2IDTo64", function( Assert )
	Assert:Equals( "76561197960267728", Shine.NS2IDTo64( 2000 ) )
end )

UnitTest:Test( "SteamID64ToNS2ID", function( Assert )
	Assert:Equals( 2000, Shine.SteamID64ToNS2ID( "76561197960267728" ) )
end )

UnitTest:Test( "CoerceToID", function( Assert )
	Assert.Equals( "Should accept numbers", 2000, Shine.CoerceToID( 2000 ) )
	Assert.Equals( "Should accept base-10 numbers as strings", 2000, Shine.CoerceToID( "2000" ) )
	Assert.Nil( "Should reject non-base 10 numbers", Shine.CoerceToID( "0xFF" ) )
	Assert.Nil( "Should reject non-numbers", Shine.CoerceToID( "nan" ) )
end )
