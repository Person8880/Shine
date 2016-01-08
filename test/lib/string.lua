--[[
	String library extension tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "StartsWith", function( Assert )
	Assert:True( string.StartsWith( "Test", "Te" ) )
	Assert:False( string.StartsWith( "Test", "te" ) )
end )

UnitTest:Test( "EndsWith", function( Assert )
	Assert:True( string.EndsWith( "Test", "est" ) )
	Assert:False( string.EndsWith( "Test", "abc" ) )
end )
