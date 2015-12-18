--[[
	Stream object tests.
]]

local UnitTest = Shine.UnitTest
local Stream = Shine.Stream

UnitTest:Test( "Reduce", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }

	Stream( Data ):Reduce( function( Value ) return Value > 3 end )

	Assert:ArrayEquals( { 4, 5, 6 }, Data )
end )

UnitTest:Test( "Map", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }

	Stream( Data ):Map( function( Value ) return -Value end )

	Assert:ArrayEquals( { -1, -2, -3, -4, -5, -6 }, Data )
end )

UnitTest:Test( "Sort", function( Assert )
	local Data = { 5, 3, 6, 4, 2, 1 }

	Stream( Data ):Sort()

	Assert:ArrayEquals( { 1, 2, 3, 4, 5, 6 }, Data )
end )
