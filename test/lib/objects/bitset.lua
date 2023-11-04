--[[
	Bitwise set object unit tests.
]]

local BitSet = Shine.BitSet
local UnitTest = Shine.UnitTest

UnitTest:Test( "Adding/removing elements", function( Assert )
	local Set = BitSet()
	for i = 0, 33 do
		Set:Add( i )
		Assert:True( Set:Contains( i ) )
	end
	Assert:Equals( 34, Set:GetCount() )
	Assert.Equals( "Set should be using 2 array values to store data", 1, Set.MaxArrayIndex )

	Set:Remove( 32 )
	Assert:False( Set:Contains( 32 ) )
	Assert:Equals( 33, Set:GetCount() )

	Set:Clear()
	for i = 0, 33 do
		Assert:False( Set:Contains( i ) )
	end
	Assert:Equals( 0, Set:GetCount() )
	Assert.Equals( "Set should have reset its max array index", 0, Set.MaxArrayIndex )
end )

UnitTest:Test( "Adding/removing a range of elements", function( Assert )
	local Set = BitSet()
	Set:AddRange( 1, 128 )
	for i = 1, 128 do
		Assert:True( Set:Contains( i ) )
	end
	Assert:Equals( 128, Set:GetCount() )

	Set:RemoveRange( 32, 64 )
	for i = 1, 31 do
		Assert:True( Set:Contains( i ) )
	end
	for i = 32, 64 do
		Assert:False( Set:Contains( i ) )
	end
	for i = 65, 128 do
		Assert:True( Set:Contains( i ) )
	end
	Assert:Equals( 95, Set:GetCount() )

	-- Adding the same range again with some overlap should only increment the size for new values.
	Set:AddRange( 1, 128 )
	for i = 1, 128 do
		Assert:True( Set:Contains( i ) )
	end
	Assert:Equals( 128, Set:GetCount() )
end )

UnitTest:Test( "Adding/removing multiple elements", function( Assert )
	local Set = BitSet()
	Set:AddAll( { 0, 1, 2, 3, 4, 5 } )
	for i = 0, 5 do
		Assert:True( Set:Contains( i ) )
	end
	Assert:Equals( 6, Set:GetCount() )

	Set:RemoveAll( { 2, 3, 4 } )
	for i = 0, 1 do
		Assert:True( Set:Contains( i ) )
	end
	for i = 2, 4 do
		Assert:False( Set:Contains( i ) )
	end
	Assert:True( Set:Contains( 5 ) )
	Assert:Equals( 3, Set:GetCount() )
end )

UnitTest:Test( "Union with another set", function( Assert )
	local Set1 = BitSet()
	local Set2 = BitSet()

	for i = 0, 64 do
		if i % 2 == 0 then
			Set2:Add( i )
			Assert:True( Set2:Contains( i ) )
			Assert:False( Set1:Contains( i ) )
		else
			Set1:Add( i )
			Assert:True( Set1:Contains( i ) )
			Assert:False( Set2:Contains( i ) )
		end
	end
	Assert:Equals( 32, Set1:GetCount() )
	Assert:Equals( 33, Set2:GetCount() )

	-- This will combine the sets, resulting in 65 elements.
	Set1:Union( Set2 )

	for i = 0, 64 do
		Assert:True( Set1:Contains( i ) )
	end
	Assert:Equals( 65, Set1:GetCount() )
end )

UnitTest:Test( "Intersection with another set", function( Assert )
	local Set1 = BitSet()
	local Set2 = BitSet()

	for i = 0, 32 do
		Set2:Add( i )
	end
	Assert:Equals( 33, Set2:GetCount() )

	for i = 0, 64 do
		Set1:Add( i )
	end
	Assert:Equals( 65, Set1:GetCount() )

	-- This will remove the last 32 elements.
	Set1:Intersection( Set2 )

	for i = 0, 32 do
		Assert:True( Set1:Contains( i ) )
	end
	for i = 33, 64 do
		Assert:False( Set1:Contains( i ) )
	end
	Assert:Equals( 33, Set1:GetCount() )
end )

UnitTest:Test( "AndNot with another set", function( Assert )
	local Set1 = BitSet()
	local Set2 = BitSet()

	for i = 0, 32 do
		Set2:Add( i )
	end
	Assert:Equals( 33, Set2:GetCount() )

	for i = 0, 64 do
		Set1:Add( i )
	end
	Assert:Equals( 65, Set1:GetCount() )

	-- This will remove the first 33 elements.
	Set1:AndNot( Set2 )

	for i = 0, 32 do
		Assert:False( Set1:Contains( i ) )
	end
	for i = 33, 64 do
		Assert:True( Set1:Contains( i ) )
	end
	Assert:Equals( 32, Set1:GetCount() )
end )

UnitTest:Test( "Iteration", function( Assert )
	local Set = BitSet()
	local ExpectedValues = {}
	for i = 0, 32 do
		if i % 2 == 0 then
			ExpectedValues[ #ExpectedValues + 1 ] = i
			Set:Add( i )
		end
	end
	for i = 128, 160 do
		if i % 2 == 0 then
			ExpectedValues[ #ExpectedValues + 1 ] = i
			Set:Add( i )
		end
	end
	Assert:Equals( #ExpectedValues, Set:GetCount() )

	local Count = 0
	for Value in Set:Iterate() do
		Count = Count + 1
		Assert:Equals( ExpectedValues[ Count ], Value )
	end
	Assert:Equals( #ExpectedValues, Count )
end )

UnitTest:Test( "__eq/__len", function( Assert )
	local Set1 = BitSet()
	local Set2 = BitSet()
	for i = 0, 33 do
		Set1:Add( i )
		Set2:Add( i )
	end
	Assert:Equals( 34, #Set1 )
	Assert:Equals( 34, #Set2 )

	Assert.Equals( "Sets should be equal with same elements", Set1, Set2 )

	Set2:Remove( 33 )

	Assert.NotEquals( "Sets should no longer be equal due to different number of elements", Set1, Set2 )

	Set1:Remove( 33 )

	Assert.Equals( "Sets should be equal again with same elements", Set1, Set2 )

	Set2:Add( 33 )
	Set1:Add( 34 )

	Assert.NotEquals( "Sets should no longer be equal due to different element values", Set1, Set2 )
end )

UnitTest:Test( "__tostring", function( Assert )
	local Set = BitSet()
	Assert:Equals( "BitSet [0 elements, MaxArrayIndex = 0]", tostring( Set ) )

	Set:Add( 1 )
	Assert:Equals( "BitSet [1 element, MaxArrayIndex = 0]", tostring( Set ) )

	Set:Add( 2 )
	Assert:Equals( "BitSet [2 elements, MaxArrayIndex = 0]", tostring( Set ) )

	Set:Add( 32 )
	Assert:Equals( "BitSet [3 elements, MaxArrayIndex = 1]", tostring( Set ) )
end )

UnitTest:Test( "BitSet.FromData", function( Assert )
	local EmptySet = BitSet.FromData( {} )
	Assert:Equals( 0, EmptySet:GetCount() )
	Assert:Equals( 0, EmptySet.MaxArrayIndex )

	local Integers = {
		1,
		2,
		4,
		8
	}

	local Set = BitSet.FromData( Integers )
	Assert:Equals( 4, Set:GetCount() )

	local ExpectedSet = BitSet()
	-- First integer sets bit 0.
	ExpectedSet:Add( 0 )
	-- Second integer sets bit 1 and starts at 32.
	ExpectedSet:Add( 33 )
	-- Third integer sets bit 2 and starts at 64.
	ExpectedSet:Add( 66 )
	-- Fourth integer sets bit 3 and starts at 96.
	ExpectedSet:Add( 99 )

	Assert:Equals( ExpectedSet, Set )
end )
