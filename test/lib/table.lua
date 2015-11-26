--[[
	Table library extension tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Reverse", function( Assert )
	local Input = { 1, 2, 3, 4, 5, 6 }
	Assert:ArrayEquals( { 6, 5, 4, 3, 2, 1 }, table.Reverse( Input ) )
end )
