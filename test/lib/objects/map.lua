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
end )

UnitTest:Test( "RemovalOfFalse", function( Assert )
	local Map = Map()
	Map:Add( 1, false )

	Assert.False( "Map didn't store false!", Map:Get( 1 ) )
	Map:Remove( 1 )
	Assert.Nil( "Map didn't remove false!", Map:Get( 1 ) )
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

		if i % 5 == 0 then
			Map:RemoveAtPosition()
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
		if i % 5 == 0 then
			Map:Remove( Key )
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
end )

UnitTest:Test( "Multimap:RemoveKeyValue()", function( Assert )
	local Map = Multimap()
	Map:Add( 1, 1 )
	Map:Add( 1, 2 )
	Map:Add( 1, 3 )

	Assert:ArrayEquals( { 1, 2, 3 }, Map:Get( 1 ) )
	Assert:Equals( 3, Map:GetCount() )

	Map:RemoveKeyValue( 1, 2 )
	Assert:ArrayEquals( { 1, 3 }, Map:Get( 1 ) )
	Assert:Equals( 2, Map:GetCount() )
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
