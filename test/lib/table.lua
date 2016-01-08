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

UnitTest:Test( "ShallowMerge", function( Assert )
	local Source = {
		Cake = true,
		MoreCake = false
	}
	local Destination = {
		Cake = false
	}

	table.ShallowMerge( Source, Destination )

	Assert:False( Destination.Cake )
	Assert:False( Destination.MoreCake )
end )

UnitTest:Test( "HasValue", function( Assert )
	local Table = {
		1, 2, 4, 3, 5, 6
	}

	local Exists, Index = table.HasValue( Table, 3 )
	Assert:True( Exists )
	Assert:Equals( 4, Index )

	Exists, Index = table.HasValue( Table, 7 )
	Assert:False( Exists )
	Assert:Nil( Index )
end )

UnitTest:Test( "InsertUnique", function( Assert )
	local Table = {
		1, 2, 3
	}

	local Inserted = table.InsertUnique( Table, 4 )
	Assert:True( Inserted )
	Assert:ArrayEquals( { 1, 2, 3, 4 }, Table )

	Inserted = table.InsertUnique( Table, 4 )
	Assert:False( Inserted )
	Assert:ArrayEquals( { 1, 2, 3, 4 }, Table )
end )

UnitTest:Test( "Build", function( Assert )
	local Base = {}
	local ReallySubChild = table.Build( Base, "Child", "SubChild", "ReallySubChild" )

	Assert:IsType( Base.Child, "table" )
	Assert:IsType( Base.Child.SubChild, "table" )
	Assert:IsType( Base.Child.SubChild.ReallySubChild, "table" )

	Assert:Equals( Base.Child.SubChild.ReallySubChild, ReallySubChild )
end )

UnitTest:Test( "QuickShuffle", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }
	table.QuickShuffle( Data )
	Assert:Equals( 6, #Data )
	for i = 1, 6 do
		Assert:NotNil( Data[ i ] )
	end
end )

UnitTest:Test( "QuickCopy", function( Assert )
	local Table = { 1, 2, {}, 4 }
	local Copy = table.QuickCopy( Table )

	Assert:NotEquals( Table, Copy )
	for i = 1, #Table do
		Assert:Equals( Table[ i ], Copy[ i ] )
	end
end )
