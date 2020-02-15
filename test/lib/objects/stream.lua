--[[
	Stream object tests.
]]

local UnitTest = Shine.UnitTest
local Stream = Shine.Stream

UnitTest:Test( "Filter", function( Assert )
	local Data = { 1, 4, 3, 5, 2, 6 }

	Stream( Data ):Filter( function( Value ) return Value > 3 end )

	Assert:ArrayEquals( { 4, 5, 6 }, Data )
end )

UnitTest:Test( "Filter with context", function( Assert )
	local Data = { 1, 4, 3, 5, 2, 6 }

	Stream( Data ):Filter( function( Value, Index, Context ) return Value > Context end, 3 )

	Assert:ArrayEquals( { 4, 5, 6 }, Data )
end )

UnitTest:Test( "ForEach", function( Assert )
	local Data = { "a", "b", "c", "d", "e", "f" }
	local Visited = {}
	local Count = 0

	Stream( Data ):ForEach( function( Value, Index, Context )
		Count = Count + 1
		Visited[ Value ] = true

		Assert:Equals( "test", Context )
	end, "test" )

	Assert:Equals( #Data, Count )
	for i = 1, Count do
		Assert:True( Visited[ Data[ i ] ] )
	end
end )

UnitTest:Test( "Map", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }

	Stream( Data ):Map( function( Value ) return -Value end )

	Assert:ArrayEquals( { -1, -2, -3, -4, -5, -6 }, Data )
end )

UnitTest:Test( "Map with context", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }

	Stream( Data ):Map( function( Value, Index, Context ) return Value * Context end, -1 )

	Assert:ArrayEquals( { -1, -2, -3, -4, -5, -6 }, Data )
end )

UnitTest:Test( "Sort", function( Assert )
	local Data = { 5, 3, 6, 4, 2, 1 }

	Stream( Data ):Sort()

	Assert:ArrayEquals( { 1, 2, 3, 4, 5, 6 }, Data )
end )

UnitTest:Test( "StableSort", function( Assert )
	local Data = { 5, 3, 6, 4, 2, 1 }

	Stream( Data ):StableSort()

	Assert:ArrayEquals( { 1, 2, 3, 4, 5, 6 }, Data )
end )

UnitTest:Test( "Limit", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }

	Stream( Data ):Limit( 3 )
	Assert:ArrayEquals( { 1, 2, 3 }, Data )

	Stream( Data ):Limit( 3 )
	Assert:ArrayEquals( { 1, 2, 3 }, Data )
end )

UnitTest:Test( "Concat", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }

	Assert:Equals( "1, 2, 3, 4, 5, 6", Stream( Data ):Concat( ", ", tostring ) )
end )

UnitTest:Test( "Reduce", function( Assert )
	local Index = 2
	local ExpectedSum = 1

	local StreamSum = Stream( { 1, 2, 3, 4, 5, 6 } ):Reduce( function( Sum, CurrentValue, StreamIndex, Context )
		Assert:Equals( Index, StreamIndex )
		Assert:Equals( ExpectedSum, Sum )
		Assert:Equals( Index, CurrentValue )
		Assert:Equals( "test", Context )

		ExpectedSum = ExpectedSum + CurrentValue
		Index = Index + 1

		return Sum + CurrentValue
	end, nil, "test" )

	Assert:Equals( 1 + 2 + 3 + 4 + 5 + 6, StreamSum )
end )

UnitTest:Test( "Reduce with start value", function( Assert )
	local Index = 1
	local ExpectedSum = 0

	local StreamSum = Stream( { 1, 2, 3, 4, 5, 6 } ):Reduce( function( Sum, CurrentValue, StreamIndex, Context )
		Assert:Equals( Index, StreamIndex )
		Assert:Equals( ExpectedSum, Sum )
		Assert:Equals( Index, CurrentValue )
		Assert.Nil( "Context value should be nil when not provided", Context )

		ExpectedSum = ExpectedSum + CurrentValue
		Index = Index + 1

		return Sum + CurrentValue
	end, 0 )

	Assert:Equals( 1 + 2 + 3 + 4 + 5 + 6, StreamSum )
end )

local function Equals( Value, Index, ExpectedValue )
	return Value == ExpectedValue
end

UnitTest:Test( "AnyMatch - Returns true if match found", function( Assert )
	Assert.True( "Should return true for a match", Stream( { 1, 2, 3, 4, 5, 6 } ):AnyMatch( Equals, 1 ) )
end )

UnitTest:Test( "AnyMatch - Returns false if no match found", function( Assert )
	Assert.False( "Should return false for no match", Stream( { 1, 2, 3, 4, 5, 6 } ):AnyMatch( Equals, 10 ) )
end )

UnitTest:Test( "Distinct", function( Assert )
	local StreamWithDuplicates = Stream( { 1, 1, 2, 2, 3, 4, 5 } )
	Assert:ArrayEquals( { 1, 2, 3, 4, 5 }, StreamWithDuplicates:Distinct():AsTable() )
end )
