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
