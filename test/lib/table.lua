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

	-- Add an inherited value.
	setmetatable( Destination, {
		__index = {
			InheritedKey = true
		}
	} )
	Source.InheritedKey = false

	-- Default is standard indexing, so it will see the inherited value.
	table.ShallowMerge( Source, Destination )

	Assert:True( Destination.InheritedKey )

	-- Now the raw flag means it will override the inherited value.
	table.ShallowMerge( Source, Destination, true )

	Assert:False( Destination.InheritedKey )
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

	-- Should not overwrite if tables already exist.
	Base.Child.Cake = true
	Assert:Equals( ReallySubChild, table.Build( Base, "Child", "SubChild", "ReallySubChild" ) )
	Assert:True( Base.Child.Cake )
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

local function GetTestTable()
	return {
		Key1 = true,
		Key2 = true,
		Key3 = true
	}
end

UnitTest:Test( "GetKeys", function( Assert )
	local Table = GetTestTable()

	local Keys, Count = table.GetKeys( Table )
	Assert:Equals( 3, Count )
	for i = 1, Count do
		Assert:True( Table[ Keys[ i ] ] )
		Table[ Keys[ i ] ] = nil
	end
end )

local function BuildIteratorTest( Iterator )
	return function( Assert )
		local Table = GetTestTable()
		local Keys = {}

		for Key, Value in Iterator( Table ) do
			Assert:True( Value )
			Assert:True( Table[ Key ] )
			Table[ Key ] = nil
			Keys[ #Keys + 1 ] = Key
		end

		return Keys
	end
end

UnitTest:Test( "RandomPairs", BuildIteratorTest( RandomPairs ) )
UnitTest:Test( "SortedPairs", function( Assert )
	local Keys = BuildIteratorTest( SortedPairs )( Assert )
	Assert:ArrayEquals( { "Key1", "Key2", "Key3" }, Keys )
end )

UnitTest:Test( "ArraysEqual", function( Assert )
	local Left = { 1, 2, 3 }
	local Right = { 1, 2, 3 }

	Assert:True( table.ArraysEqual( Left, Right ) )

	Left[ 4 ] = 5
	Right[ 4 ] = 4
	Assert:False( table.ArraysEqual( Left, Right ) )

	Left[ 4 ] = 4
	Right[ 5 ] = 5
	Assert:False( table.ArraysEqual( Left, Right ) )
end )

UnitTest:Test( "AsEnum", function( Assert )
	local Values = {
		"This", "Is", "An", "Enum"
	}
	local Enum = table.AsEnum( Values )
	Assert:ArrayEquals( Values, Enum )
	for i = 1, #Values do
		Assert:Equals( Values[ i ], Enum[ Values[ i ] ] )
	end
end )
