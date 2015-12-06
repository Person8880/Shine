--[[
	Table library extension tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Reverse", function( Assert )
	local Input = { 1, 2, 3, 4, 5, 6 }
	Assert:ArrayEquals( { 6, 5, 4, 3, 2, 1 }, table.Reverse( Input ) )
end )

UnitTest:Test( "RemoveByValue", function( Assert )
	local Input = { 1, 2, 3, 4, 5, 6 }
	table.RemoveByValue( Input, 3 )

	Assert:ArrayEquals( { 1, 2, 4, 5, 6 }, Input )
end )

UnitTest:Test( "Mixin", function( Assert )
	local Source = {
		Cake = true,
		MoreCake = true,
		SoMuchCake = true
	}
	local Destination = {}
	table.Mixin( Source, Destination, {
		"Cake", "MoreCake"
	} )

	Assert:True( Destination.Cake )
	Assert:True( Destination.MoreCake )
	Assert:Nil( Destination.SoMuchCake )
end )
