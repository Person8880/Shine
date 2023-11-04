--[[
	Map test.
]]

local UnitTest = Shine.UnitTest

local function RunMapTests( TypeName, MapType )
	UnitTest:Test( TypeName.." - Size", function( Assert )
		local Map = MapType()

		for i = 1, 30 do
			Map:Add( i, i )
		end

		Assert.Equals( "Map has incorrect size after adding!", 30, Map:GetCount() )

		for i = 1, 5 do
			Map:RemoveAtPosition( 1 )
		end

		Assert.Equals( "Map has incorrect size after removing!", 25, Map:GetCount() )
	end )

	UnitTest:Test( TypeName.." - IterationOrder", function( Assert )
		local Map = MapType()

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

	UnitTest:Test( TypeName.." - RemovalOfFalse", function( Assert )
		local Map = MapType()
		Map:Add( 1, false )

		Assert.False( "Map didn't store false!", Map:Get( 1 ) )
		Map:Remove( 1 )
		Assert.Nil( "Map didn't remove false!", Map:Get( 1 ) )
	end )

	UnitTest:Test( TypeName.." - Clear", function( Assert )
		local Map = MapType()
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

	UnitTest:Test( TypeName.." - Filter", function( Assert )
		local Map = MapType()
		local ExpectedValues = {}

		for i = 1, 30 do
			ExpectedValues[ i ] = "Test "..i
			Map:Add( i, ExpectedValues[ i ] )
		end

		Assert:Equals( 30, Map:GetCount() )

		local SeenKeys = {}
		Map:Filter( function( Key, Value, Context )
			Assert:Same( Map, Context )
			SeenKeys[ Key ] = Value
			return Key > 15
		end, Map )
		Assert:DeepEquals( ExpectedValues, SeenKeys )

		Assert:Equals( 15, Map:GetCount() )
		for i = 1, 15 do
			Assert:Nil( Map:Get( i ) )
		end
		local ExpectedKeys = {}
		for i = 16, 30 do
			ExpectedKeys[ #ExpectedKeys + 1 ] = i
			Assert:Equals( "Test "..i, Map:Get( i ) )
		end
		Assert:ArrayEquals( ExpectedKeys, Map.Keys )
	end )

	if TypeName == "Map" then
		UnitTest:Test( TypeName.." - IterationRemoval", function( Assert )
			local Map = MapType()

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
	else
		UnitTest:Test( TypeName.." - IterationRemoval", function( Assert )
			local Map = MapType()

			for i = 1, 30 do
				Map:Add( i, i )
			end

			local SeenValues = {}
			local i = 0
			while Map:HasNext() do
				i = i + 1

				local Value = Map:GetNext()
				SeenValues[ Value ] = true

				if i % 5 == 0 then
					Map:RemoveAtPosition()
					Assert.Nil( "Should have removed the value", Map:Get( Value ) )
				end
			end

			Assert.Equals( "Didn't iterate enough times!", 30, i )
			for i = 1, 30 do
				Assert.True( i.." should have been seen during iteration", SeenValues[ i ] )
			end
		end )
	end

	UnitTest:Test( TypeName.." - GenericFor", function( Assert )
		local Map = MapType()

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

	UnitTest:Test( TypeName.." - GenericForRemoval", function( Assert )
		local Map = MapType()

		for i = 1, 30 do
			Map:Add( i, i )
		end

		local Done = {}
		local i = 0
		for Key, Value in Map:Iterate() do
			Assert.Falsy( "Generic for is iterating elements multiple times!", Done[ Key ] )

			i = i + 1

			if TypeName == "Map" then
				Assert.Equals( "Generic for removal resulted in repeated values", i, Value )
			end

			if i % 5 == 0 then
				Map:Remove( Key )
				Assert.Nil( "Key was not removed as expected", Map:Get( Key ) )
			end

			Done[ Key ] = true
		end

		Assert.Equals( "Didn't iterate enough times!", 30, i )
		for i = 1, 30 do
			Assert.True( i.." should have been seen during iteration", Done[ i ] )
		end
	end )

	UnitTest:Test( TypeName.." - GenericForBackwards", function( Assert )
		local Map = MapType()

		for i = 1, 30 do
			Map:Add( i, i )
		end

		local Done = {}
		local i = 31
		local IterCount = 0

		for Key, Value in Map:IterateBackwards() do
			Assert.Falsy( "Generic for backwards is iterating elements multiple times!", Done[ Key ] )

			i = i - 1
			IterCount = IterCount + 1

			if TypeName == "Map" then
				Assert.Equals( "Generic for backwards doesn't iterate in order!", i, Key )
				Assert.Equals( "Generic for backwards doesn't iterate in order!", i, Value )
			end

			if i % 5 == 0 then
				Map:Remove( Key )
				Assert.Nil( "Key was not removed as expected", Map:Get( Key ) )
			end

			Done[ Key ] = true
		end

		Assert.Equals( "Didn't iterate enough times!", 30, IterCount )
		for i = 1, 30 do
			Assert.True( i.." should have been seen during iteration", Done[ i ] )
		end
	end )

	UnitTest:Test( TypeName.." - EmptyMapIterators", function( Assert )
		local Map = MapType()

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

	UnitTest:Test( TypeName.." - Construct with map", function( Assert )
		local InitialMap = MapType()
		InitialMap:Add( "Test", "Value" )
		InitialMap:Add( "AnotherTest", "AnotherValue" )

		local Copy = MapType( InitialMap )
		Assert:Equals( 2, Copy:GetCount() )
		Assert:Equals( "Value", Copy:Get( "Test" ) )
		Assert:Equals( "AnotherValue", Copy:Get( "AnotherTest" ) )
	end )

	UnitTest:Test( TypeName.." - Construct with table", function( Assert )
		local InitialValues = {
			Test = "Value",
			AnotherTest = "AnotherValue"
		}

		local Copy = MapType( InitialValues )
		Assert:Equals( 2, Copy:GetCount() )
		Assert:Equals( "Value", Copy:Get( "Test" ) )
		Assert:Equals( "AnotherValue", Copy:Get( "AnotherTest" ) )
	end )

	UnitTest:Test( TypeName.." - SortKeys", function( Assert )
		local Map = MapType()
		Map:Add( "Z", 789 )
		Map:Add( "B", 456 )
		Map:Add( "A", 123 )

		Assert.ArrayEquals( "Initial keys should follow insertion order", { "Z", "B", "A" }, Map.Keys )

		Map:SortKeys( function( A, B ) return A < B end )

		Assert.ArrayEquals( "Should have sorted keys in ascending order", { "A", "B", "Z" }, Map.Keys )
	end )

	UnitTest:Test( TypeName.." - StableSortKeys", function( Assert )
		local Map = MapType()
		Map:Add( "Z", 789 )
		Map:Add( "B", 456 )
		Map:Add( "A", 123 )

		Assert.ArrayEquals( "Initial keys should follow insertion order", { "Z", "B", "A" }, Map.Keys )

		Map:StableSortKeys( function( A, B )
			return A == B and 0 or ( A < B and -1 or 1 )
		end )

		Assert.ArrayEquals( "Should have sorted keys in ascending order", { "A", "B", "Z" }, Map.Keys )
	end )

	UnitTest:Test( TypeName.." - AsTable", function( Assert )
		local Map = MapType{
			A = 1, B = 2, C = 3
		}

		Assert.DeepEquals( "Should convert map to table as expected", {
			A = 1, B = 2, C = 3
		}, Map:AsTable() )
	end )

	UnitTest:Test( TypeName.." - __eq", function( Assert )
		local Map1 = MapType()
		Map1:Add( "test 1", 1 )
		Map1:Add( "test 2", 2 )
		Map1:Add( "test 3", 3 )

		local Map2 = MapType()
		Map2:Add( "test 1", 1 )
		Map2:Add( "test 2", 2 )
		Map2:Add( "test 3", 3 )

		Assert.Equals( "Maps with the same key-values should be considered equal", Map1, Map2 )

		Map2:Add( "test 2", 4 )
		Assert.NotEquals( "Maps with different values under the same key should not be considered equal", Map1, Map2 )

		Map2:Remove( "test 2" )
		Assert.NotEquals( "Maps with different numbers of keys should not be considered equal", Map1, Map2 )
	end )
end
RunMapTests( "Map", Shine.Map )
RunMapTests( "UnorderedMap", Shine.UnorderedMap )

local function RunMultimapTests( TypeName, MultimapType, MapType )
	UnitTest:Test( TypeName.." - Multimap:Add()/AddPair()/Get()/GetPairValue()/GetPairs()/GetCount()", function( Assert )
		local Map = MultimapType()

		Map:Add( 1, 1 )
		Map:Add( 1, 2 )
		Map:AddPair( 1, 3, 4 )
		Map:Add( 2, 1 )
		Map:Add( 3, 1 )
		Map:AddPair( 3, 2, "test" )

		Assert:ArrayEquals( { 1, 2, 3 }, Map:Get( 1 ) )
		Assert:Equals( MapType{ 1, 2, 4 }, Map:GetPairs( 1 ) )

		Assert:ArrayEquals( { 1 }, Map:Get( 2 ) )
		Assert:Equals( MapType{ 1 }, Map:GetPairs( 2 ) )

		Assert:ArrayEquals( { 1, 2 }, Map:Get( 3 ) )
		Assert:Equals( MapType{ 1, "test" }, Map:GetPairs( 3 ) )

		for i = 1, 3 do
			Assert.True( "Should have expected key-values", Map:HasKeyValue( 1, i ) )
		end

		Assert.Equals( "Should retrieve the paired value for a key", 4, Map:GetPairValue( 1, 3 ) )

		Assert.True( "Should have expected key-values", Map:HasKeyValue( 2, 1 ) )

		for i = 1, 2 do
			Assert.True( "Should have expected key-values", Map:HasKeyValue( 3, i ) )
		end

		Assert.Equals( "Should retrieve the paired value for a key", "test", Map:GetPairValue( 3, 2 ) )

		Assert.False( "Should return false for a key-value that is not in the multimap", Map:HasKeyValue( 4, 1 ) )
		Assert.Nil(
			"Should return a nil pair value for a key-value that is not in the multimap",
			Map:GetPairValue( 4, 1 )
		)

		Assert:Equals( 6, Map:GetCount() )
		Assert:Equals( 3, Map:GetKeyCount() )
	end )

	UnitTest:Test( TypeName.." - Multimap:RemoveKeyValue()", function( Assert )
		local Map = MultimapType()
		Map:Add( 1, 1 )
		Map:Add( 1, 2 )
		Map:AddPair( 1, 3, true )

		Assert:ArrayEquals( { 1, 2, 3 }, Map:Get( 1 ) )
		Assert:Equals( MapType{ 1, 2, true }, Map:GetPairs( 1 ) )
		Assert:Equals( 3, Map:GetCount() )
		Assert:Equals( 1, Map:GetKeyCount() )

		Map:RemoveKeyValue( 1, 1 )
		Assert:ArrayEquals( TypeName == "Multimap" and { 2, 3 } or { 3, 2 }, Map:Get( 1 ) )
		Assert:Equals( MapType{ nil, 2, true }, Map:GetPairs( 1 ) )
		Assert:Equals( 2, Map:GetCount() )
		Assert:Equals( 1, Map:GetKeyCount() )

		Map:RemoveKeyValue( 1, 2 )
		Map:RemoveKeyValue( 1, 3 )
		Assert:Nil( Map:Get( 1 ) )
		Assert:Nil( Map:GetPairs( 1 ) )
		Assert:Equals( 0, Map:GetCount() )
		Assert:Equals( 0, Map:GetKeyCount() )
	end )

	UnitTest:Test( TypeName.." - Multimap:Clear()", function( Assert )
		local Map = MultimapType()
		for i = 1, 30 do
			Map:Add( i % 2, i )
		end

		Assert:Equals( 30, Map:GetCount() )

		Map:Clear()

		Assert:Nil( Map:Get( 0 ) )
		Assert:Nil( Map:GetPairs( 0 ) )
		Assert:Nil( Map:Get( 1 ) )
		Assert:Nil( Map:GetPairs( 1 ) )

		Assert.True( "Map was not empty after clearing", Map:IsEmpty() )
		Assert.Equals( "Map was not empty after clearing", 0, Map:GetCount() )
	end )

	UnitTest:Test( TypeName.." - Multimap from table", function( Assert )
		local Map = MultimapType{
			{ 1, 2, 3 }, { 1 }, { 1, 2 }
		}

		Assert:ArrayEquals( { 1, 2, 3 }, Map:Get( 1 ) )
		Assert:ArrayEquals( { 1 }, Map:Get( 2 ) )
		Assert:ArrayEquals( { 1, 2 }, Map:Get( 3 ) )

		Assert:Equals( 6, Map:GetCount() )
	end )

	UnitTest:Test( TypeName.." - Multimap from multimap", function( Assert )
		local Map = MultimapType()
		Map:Add( 1, 1 )
		Map:Add( 1, 2 )
		Map:AddPair( 1, 3, true )

		local Map2 = MultimapType( Map )
		Assert:ArrayEquals( { 1, 2, 3 }, Map2:Get( 1 ) )
		Assert:Equals( MapType{ 1, 2, true }, Map2:GetPairs( 1 ) )
		Assert:Equals( 3, Map2:GetCount() )
	end )

	UnitTest:Test( TypeName.." - Multimap:Iterate()/IterateBackwards()", function( Assert )
		local Map = MultimapType()
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

	UnitTest:Test( TypeName.." - Multimap:IteratePairs()/IteratePairsBackwards()", function( Assert )
		local Map = MultimapType()
		Map:AddPair( 1, 1, "test 1" )
		Map:AddPair( 1, 2, "test 2" )
		Map:AddPair( 1, 3, "test 3" )
		Map:AddPair( 2, 1, "test 4" )
		Map:AddPair( 2, 2, "test 5" )
		Map:AddPair( 3, 1, "test 6" )

		local ExpectedValues = {
			MapType{ "test 1", "test 2", "test 3" },
			MapType{ "test 4", "test 5" },
			MapType{ "test 6" }
		}

		local Index = 0
		for Key, Values in Map:IteratePairs() do
			Index = Index + 1
			Assert:Equals( Index, Key )
			Assert:Equals( ExpectedValues[ Key ], Values )
		end

		for Key, Values in Map:IteratePairsBackwards() do
			Assert:Equals( Index, Key )
			Assert:Equals( ExpectedValues[ Key ], Values )
			Index = Index - 1
		end
	end )

	UnitTest:Test( TypeName.." - Multimap:AddAll()", function( Assert )
		local Map = MultimapType()
		Map:AddAll( "A", { 1, 2, 3, 4 } )

		Assert.DeepEquals( "Should assign all values to the given key", {
			A = { 1, 2, 3, 4 }
		}, Map:AsTable() )
	end )

	UnitTest:Test( TypeName.." - Multimap:CopyFrom()", function( Assert )
		local Map1 = MultimapType{
			A = { 1, 2, 3 },
			B = { 4, 5, 6 }
		}

		Map1:CopyFrom( MultimapType{
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

	UnitTest:Test( TypeName.." - __eq", function( Assert )
		local Map1 = MultimapType()
		Map1:Add( "test 1", 1 )
		Map1:Add( "test 1", 2 )
		Map1:AddPair( "test 2", 3, "test" )

		local Map2 = MultimapType()
		Map2:Add( "test 1", 1 )
		Map2:Add( "test 1", 2 )
		Map2:AddPair( "test 2", 3, "test" )

		Assert.Equals( "Multimaps with the same key-values should be considered equal", Map1, Map2 )

		Map2:AddPair( "test 2", 3, "something else" )
		Assert.NotEquals(
			"Multimaps with different paired values under the same key-value should not be considered equal",
			Map1,
			Map2
		)

		Map2:Remove( "test 2" )
		Assert.NotEquals( "Maps with different numbers of keys should not be considered equal", Map1, Map2 )

		Map2:AddPair( "test 2", 3, "test" )
		Map2:AddPair( "test 2", 4, "test 2" )
		Assert.NotEquals(
			"Maps with different numbers of value pairs under a key should not be considered equal",
			Map1,
			Map2
		)
	end )
end
RunMultimapTests( "Multimap", Shine.Multimap, Shine.Map )
RunMultimapTests( "UnorderedMultimap", Shine.UnorderedMultimap, Shine.UnorderedMap )
