--[[
	Map test.
]]

local UnitTest = Shine.UnitTest

local Map = Shine.Map

UnitTest:Test( "Size", function( Assert )
	local Map = Map()

	for i = 1, 30 do
		Map:Add( i, i )
	end

	Assert.Equals( "Map has incorrect size after adding!", 30, Map:GetCount() )

	for i = 1, 5 do
		Map:RemoveAtPosition( 1 )
	end

	Assert.Equals( "Map has incorrect size after removing!", 25, Map:GetCount() )
end )

UnitTest:Test( "IterationOrder", function( Assert )
	local Map = Map()

	for i = 1, 30 do
		Map:Add( i, i )
	end

	local i = 1
	while Map:HasNext() do
		local Key, Value = Map:GetNext()

		Assert.Equals( "Not iterating up the Map in order!", i, Key )
		Assert.Equals( "Not iterating up the Map in order!", i, Value )

		i = i + 1
	end
	Assert.Equals( "Didn't iterate through the expected number of keys", 31, i )
end )

UnitTest:Test( "RemovalOfFalse", function( Assert )
	local Map = Map()
	Map:Add( 1, false )

	Assert.False( "Map didn't store false!", Map:Get( 1 ) )
	Map:Remove( 1 )
	Assert.Nil( "Map didn't remove false!", Map:Get( 1 ) )
end )

UnitTest:Test( "Clear", function( Assert )
	local Map = Map()
	for i = 1, 30 do
		Map:Add( i, i )
	end

	Assert:Equals( 30, Map:GetCount() )

	Map:Clear()

	for i = 1, 30 do
		Assert:Nil( Map:Get( i ) )
	end

	Assert.True( "Map was not empty after clearing", Map:IsEmpty() )
	Assert.Equals( "Map was not empty after clearing", 0, Map:GetCount() )
end )

UnitTest:Test( "IterationRemoval", function( Assert )
	local Map = Map()

	for i = 1, 30 do
		Map:Add( i, i )
	end

	local i = 0
	while Map:HasNext() do
		i = i + 1

		local Value = Map:GetNext()
		Assert.Equals( "Unexpected iteration value", i, Value )

		if i % 5 == 0 then
			Map:RemoveAtPosition()
			Assert.Nil( "Should have removed the value", Map:Get( i ) )
		end
	end

	Assert.Equals( "Didn't iterate enough times!", 30, i )
end )

UnitTest:Test( "GenericFor", function( Assert )
	local Map = Map()

	for i = 1, 30 do
		Map:Add( i, i )
	end

	local i = 0
	for Key, Value in Map:Iterate() do
		i = i + 1
		Assert.Equals( "Generic for doesn't iterate in order!", i, Key )
		Assert.Equals( "Generic for doesn't iterate in order!", i, Value )
	end

	Assert.Equals( "Didn't iterate enough times!", 30, i )
end )

UnitTest:Test( "GenericForRemoval", function( Assert )
	local Map = Map()

	for i = 1, 30 do
		Map:Add( i, i )
	end

	local Done = {}
	local i = 0
	for Key, Value in Map:Iterate() do
		Assert.Falsy( "Generic for is iterating elements multiple times!", Done[ Key ] )

		i = i + 1
		Assert.Equals( "Generic for removal resulted in repeated values", i, Value )

		if i % 5 == 0 then
			Map:Remove( Key )
			Assert.Nil( "Key was not removed as expected", Map:Get( Key ) )
		end

		Done[ Key ] = true
	end

	Assert.Equals( "Didn't iterate enough times!", 30, i )
end )

UnitTest:Test( "GenericForBackwards", function( Assert )
	local Map = Map()

	for i = 1, 30 do
		Map:Add( i, i )
	end

	local Done = {}
	local i = 31
	local IterCount = 0

	for Key, Value in Map:IterateBackwards() do
		i = i - 1
		IterCount = IterCount + 1
		Assert.Equals( "Generic for backwards doesn't iterate in order!", i, Key )
		Assert.Equals( "Generic for backwards doesn't iterate in order!", i, Value )
	end

	Assert.Equals( "Didn't iterate enough times!", 30, IterCount )
end )

UnitTest:Test( "EmptyMapIterators", function( Assert )
	local Map = Map()

	local i = 0

	for Key, Value in Map:Iterate() do
		i = i + 1
	end

	Assert.Equals( "Generic for on an empty map iterated > 0 times!", 0, i )

	for Key, Value in Map:IterateBackwards() do
		i = i + 1
	end

	Assert.Equals( "Generic for backwards on an empty map iterated > 0 times!", 0, i )
end )

UnitTest:Test( "Construct with map", function( Assert )
	local InitialMap = Map()
	InitialMap:Add( "Test", "Value" )
	InitialMap:Add( "AnotherTest", "AnotherValue" )

	local Copy = Map( InitialMap )
	Assert:Equals( 2, Copy:GetCount() )
	Assert:Equals( "Value", Copy:Get( "Test" ) )
	Assert:Equals( "AnotherValue", Copy:Get( "AnotherTest" ) )
end )

UnitTest:Test( "Construct with table", function( Assert )
	local InitialValues = {
		Test = "Value",
		AnotherTest = "AnotherValue"
	}

	local Copy = Map( InitialValues )
	Assert:Equals( 2, Copy:GetCount() )
	Assert:Equals( "Value", Copy:Get( "Test" ) )
	Assert:Equals( "AnotherValue", Copy:Get( "AnotherTest" ) )
end )

UnitTest:Test( "SortKeys", function( Assert )
	local Map = Map()
	Map:Add( "Z", 789 )
	Map:Add( "B", 456 )
	Map:Add( "A", 123 )

	Assert.ArrayEquals( "Initial keys should follow insertion order", { "Z", "B", "A" }, Map.Keys )

	Map:SortKeys( function( A, B ) return A < B end )

	Assert.ArrayEquals( "Should have sorted keys in ascending order", { "A", "B", "Z" }, Map.Keys )
end )

UnitTest:Test( "StableSortKeys", function( Assert )
	local Map = Map()
	Map:Add( "Z", 789 )
	Map:Add( "B", 456 )
	Map:Add( "A", 123 )

	Assert.ArrayEquals( "Initial keys should follow insertion order", { "Z", "B", "A" }, Map.Keys )

	Map:StableSortKeys( function( A, B )
		return A == B and 0 or ( A < B and -1 or 1 )
	end )

	Assert.ArrayEquals( "Should have sorted keys in ascending order", { "A", "B", "Z" }, Map.Keys )
end )

UnitTest:Test( "AsTable", function( Assert )
	local Map = Map{
		A = 1, B = 2, C = 3
	}

	Assert.DeepEquals( "Should convert map to table as expected", {
		A = 1, B = 2, C = 3
	}, Map:AsTable() )
end )

local Multimap = Shine.Multimap

UnitTest:Test( "Multimap:Add()/Get()/GetCount()", function( Assert )
	local Map = Multimap()

	Map:Add( 1, 1 )
	Map:Add( 1, 2 )
	Map:Add( 1, 3 )
	Map:Add( 2, 1 )
	Map:Add( 3, 1 )
	Map:Add( 3, 2 )

	Assert:ArrayEquals( { 1, 2, 3 }, Map:Get( 1 ) )
	Assert:ArrayEquals( { 1 }, Map:Get( 2 ) )
	Assert:ArrayEquals( { 1, 2 }, Map:Get( 3 ) )

	Assert:Equals( 6, Map:GetCount() )
	Assert:Equals( 3, Map:GetKeyCount() )
end )

UnitTest:Test( "Multimap:RemoveKeyValue()", function( Assert )
	local Map = Multimap()
	Map:Add( 1, 1 )
	Map:Add( 1, 2 )
	Map:Add( 1, 3 )

	Assert:ArrayEquals( { 1, 2, 3 }, Map:Get( 1 ) )
	Assert:Equals( 3, Map:GetCount() )
	Assert:Equals( 1, Map:GetKeyCount() )

	Map:RemoveKeyValue( 1, 2 )
	Assert:ArrayEquals( { 1, 3 }, Map:Get( 1 ) )
	Assert:Equals( 2, Map:GetCount() )
	Assert:Equals( 1, Map:GetKeyCount() )

	Map:RemoveKeyValue( 1, 1 )
	Map:RemoveKeyValue( 1, 3 )
	Assert:Equals( 0, Map:GetCount() )
	Assert:Equals( 0, Map:GetKeyCount() )
end )

UnitTest:Test( "Multimap:Clear()", function( Assert )
	local Map = Multimap()
	for i = 1, 30 do
		Map:Add( i % 2, i )
	end

	Assert:Equals( 30, Map:GetCount() )

	Map:Clear()

	Assert:Nil( Map:Get( 0 ) )
	Assert:Nil( Map:Get( 1 ) )

	Assert.True( "Map was not empty after clearing", Map:IsEmpty() )
	Assert.Equals( "Map was not empty after clearing", 0, Map:GetCount() )
end )

UnitTest:Test( "Multimap from table", function( Assert )
	local Map = Multimap{
		{ 1, 2, 3 }, { 1 }, { 1, 2 }
	}

	Assert:ArrayEquals( { 1, 2, 3 }, Map:Get( 1 ) )
	Assert:ArrayEquals( { 1 }, Map:Get( 2 ) )
	Assert:ArrayEquals( { 1, 2 }, Map:Get( 3 ) )

	Assert:Equals( 6, Map:GetCount() )
end )

UnitTest:Test( "Multimap from multimap", function( Assert )
	local Map = Multimap()
	Map:Add( 1, 1 )
	Map:Add( 1, 2 )
	Map:Add( 1, 3 )

	local Map2 = Multimap( Map )
	Assert:ArrayEquals( { 1, 2, 3 }, Map2:Get( 1 ) )
	Assert:Equals( 3, Map2:GetCount() )
end )

UnitTest:Test( "Multimap:Iterate()/IterateBackwards()", function( Assert )
	local Map = Multimap()
	Map:Add( 1, 1 )
	Map:Add( 1, 2 )
	Map:Add( 1, 3 )
	Map:Add( 2, 1 )
	Map:Add( 2, 2 )
	Map:Add( 3, 1 )

	local ExpectedValues = {
		{ 1, 2, 3 },
		{ 1, 2 },
		{ 1 }
	}

	local Index = 0
	for Key, Values in Map:Iterate() do
		Index = Index + 1
		Assert:Equals( Index, Key )
		Assert:ArrayEquals( ExpectedValues[ Key ], Values )
	end

	for Key, Values in Map:IterateBackwards() do
		Assert:Equals( Index, Key )
		Assert:ArrayEquals( ExpectedValues[ Key ], Values )
		Index = Index - 1
	end
end )

UnitTest:Test( "Multimap:AddAll()", function( Assert )
	local Map = Multimap()
	Map:AddAll( "A", { 1, 2, 3, 4 } )

	Assert.DeepEquals( "Should assign all values to the given key", {
		A = { 1, 2, 3, 4 }
	}, Map:AsTable() )
end )

UnitTest:Test( "Multimap:CopyFrom()", function( Assert )
	local Map1 = Multimap{
		A = { 1, 2, 3 },
		B = { 4, 5, 6 }
	}

	Map1:CopyFrom( Multimap{
		A = { 4, 5, 6 },
		B = { 1, 2, 3 },
		C = { 7, 8, 9 }
	} )

	Assert.DeepEquals( "Should have merged values as expected", {
		A = { 1, 2, 3, 4, 5, 6 },
		B = { 4, 5, 6, 1, 2, 3 },
		C = { 7, 8, 9 }
	}, Map1:AsTable() )
end )
