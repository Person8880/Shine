--[[
	Queue object unit tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Add", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )

	Assert.Equals( "Value at index 1 should equal 1", 1, Queue.Elements[ 1 ] )
	Assert.Equals( "First index should be 1", 1, Queue.First )
	Assert.Equals( "Last index should be 1", 1, Queue.Last )
	Assert.Equals( "Size should be 1", 1, Queue:GetCount() )

	Queue:Add( 2 )
	Assert.Equals( "Value at index 1 should equal 1", 1, Queue.Elements[ 1 ] )
	Assert.Equals( "Value at index 1 should equal 2", 2, Queue.Elements[ 2 ] )
	Assert.Equals( "First index should be 1", 1, Queue.First )
	Assert.Equals( "Last index should be 2", 2, Queue.Last )
	Assert.Equals( "Size should be 2", 2, Queue:GetCount() )
end )

UnitTest:Test( "InsertAtFront", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )
	Queue:Add( 2 )
	Queue:Add( 3 )

	Queue:InsertAtFront( 4 )

	Assert.DeepEquals( "Should have inserted 4 behind the first element", {
		[ 0 ] = 4, 1, 2, 3
	}, Queue.Elements )
	Assert.Equals( "First index should be 0", 0, Queue.First )
	Assert.Equals( "Last index should be 3", 3, Queue.Last )
	Assert.Equals( "Size should be 4", 4, Queue:GetCount() )
end )

UnitTest:Test( "InsertAtIndex", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )
	Queue:Add( 2 )
	Queue:Add( 3 )

	Queue:InsertAtIndex( 2, 4 )

	Assert.ArrayEquals( "Should have inserted 4 at the 2nd position", {
		1, 4, 2, 3
	}, Queue.Elements )
	Assert.Equals( "First index should be 1", 1, Queue.First )
	Assert.Equals( "Last index should be 4", 4, Queue.Last )
	Assert.Equals( "Size should be 4", 4, Queue:GetCount() )
end )

UnitTest:Test( "InsertByComparing - At front", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )
	Queue:Add( 2 )
	Queue:Add( 3 )

	Queue:InsertByComparing( 0, function( A, B ) return A < B end )

	Assert.ArrayEquals( "Should have inserted 0 at the 1st position", {
		0, 1, 2, 3
	}, Queue.Elements )
	Assert.Equals( "First index should be 1", 1, Queue.First )
	Assert.Equals( "Last index should be 4", 4, Queue.Last )
	Assert.Equals( "Size should be 4", 4, Queue:GetCount() )
end )

UnitTest:Test( "InsertByComparing - At middle", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )
	Queue:Add( 2 )
	Queue:Add( 5 )

	Queue:InsertByComparing( 4, function( A, B ) return A < B end )

	Assert.ArrayEquals( "Should have inserted 4 at the last position", {
		1, 2, 4, 5
	}, Queue.Elements )
	Assert.Equals( "First index should be 1", 1, Queue.First )
	Assert.Equals( "Last index should be 4", 4, Queue.Last )
	Assert.Equals( "Size should be 4", 4, Queue:GetCount() )
end )

UnitTest:Test( "InsertByComparing - At back", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )
	Queue:Add( 2 )
	Queue:Add( 3 )

	Queue:InsertByComparing( 6, function( A, B ) return A < B end )

	Assert.ArrayEquals( "Should have inserted 4 at the last position", {
		1, 2, 3, 6
	}, Queue.Elements )
	Assert.Equals( "First index should be 1", 1, Queue.First )
	Assert.Equals( "Last index should be 4", 4, Queue.Last )
	Assert.Equals( "Size should be 4", 4, Queue:GetCount() )
end )

UnitTest:Test( "Remove", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )
	Queue:Add( 2 )
	Queue:Add( 2 )
	Queue:Add( 3 )

	Assert.Equals( "Should have 4 elements", 4, Queue:GetCount() )
	Assert.ArrayEquals( "Elements should be as expected", {
		1, 2, 2, 3
	}, Queue.Elements )
	Assert.Equals( "First index should be 1", 1, Queue.First )
	Assert.Equals( "Last index should be 4", 4, Queue.Last )

	Assert.True( "Should find and remove 2", Queue:Remove( 2 ) )

	Assert.Equals( "Should have 2 elements", 2, Queue:GetCount() )
	Assert.ArrayEquals( "Elements should be as expected", {
		1, 3
	}, Queue.Elements )
	Assert.Equals( "First index should still be 1", 1, Queue.First )
	Assert.Equals( "Last index should now be 2", 2, Queue.Last )

	Assert.False( "Should not find 2 again", Queue:Remove( 2 ) )

	Queue:Add( 2 )
	Queue:Add( 2 )

	Assert.Equals( "Should pop 1", 1, Queue:Pop() )
	Assert.True( "Should remove 2 again", Queue:Remove( 2 ) )

	Assert.Equals( "Should have 1 element", 1, Queue:GetCount() )
	Assert.Equals( "First index should be 2", 2, Queue.First )
	Assert.Equals( "Last index should be 2", 2, Queue.Last )
	Assert.Equals( "3 should be at the front of the queue", 3, Queue:Peek() )
	Assert.DeepEquals( "Should only be a single element left", {
		[ 2 ] = 3
	}, Queue.Elements )
end )

UnitTest:Test( "Pop", function( Assert )
	local Queue = Shine.Queue()
	for i = 1, 5 do
		Queue:Add( i )
	end

	for i = 1, 4 do
		Assert:Equals( i, Queue:Pop() )

		local FirstValue = Queue:Peek()
		Assert:Equals( i + 1, FirstValue )
		Assert:Equals( 5 - i, Queue:GetCount() )
	end

	Assert:Equals( 5, Queue:Pop() )
	Assert:Nil( Queue:Peek() )
	Assert:Equals( 0, Queue:GetCount() )

	Assert:Nil( Queue:Pop() )
end )

UnitTest:Test( "Get", function( Assert )
	local Queue = Shine.Queue()
	for i = 1, 5 do
		Queue:Add( i + 5 )
		Assert.Equals( "Should return element at index "..i, i + 5, Queue:Get( i ) )
	end
end )

UnitTest:Test( "IndexOf", function( Assert )
	local Queue = Shine.Queue()
	for i = 1, 5 do
		Queue:Add( i % 2 )
	end

	Assert.Equals( "Should find the first index for value 1", 1, Queue:IndexOf( 1 ) )
	Assert.Equals( "Should find the first index for value 0", 2, Queue:IndexOf( 0 ) )
end )

UnitTest:Test( "LastIndexOf", function( Assert )
	local Queue = Shine.Queue()
	for i = 1, 5 do
		Queue:Add( i % 2 )
	end

	Assert.Equals( "Should find the last index for value 1", 5, Queue:LastIndexOf( 1 ) )
	Assert.Equals( "Should find the last index for value 0", 4, Queue:LastIndexOf( 0 ) )
end )

UnitTest:Test( "Clear", function( Assert )
	local Queue = Shine.Queue()
	for i = 1, 5 do
		Queue:Add( i )
	end

	Assert:Equals( 5, Queue:GetCount() )

	Queue:Clear()
	Assert:Nil( Queue:Peek() )
	Assert:Equals( 0, Queue:GetCount() )
end )

UnitTest:Test( "Iterate", function( Assert )
	local Queue = Shine.Queue()
	local ExpectedIterations = 20
	for i = 1, ExpectedIterations do
		Queue:Add( i )
	end

	local i = 0
	for Value in Queue:Iterate() do
		i = i + 1
		Assert:Equals( i, Value )
	end
	Assert:Equals( ExpectedIterations, i )
end )

UnitTest:Test( "EmptyIterate", function( Assert )
	local Queue = Shine.Queue()
	local i = 0
	for Value in Queue:Iterate() do
		i = i + 1
	end
	Assert:Equals( 0, i )
end )

UnitTest:Test( "Add, then pop, then add", function( Assert )
	local Data = {}
	local Queue = Shine.Queue()

	Queue:Add( Data )
	Assert:Equals( 1, Queue:GetCount() )
	Assert:Equals( Data, Queue:Peek() )

	Assert:Equals( Data, Queue:Pop() )
	Assert:Equals( 0, Queue:GetCount() )
	Assert:Nil( Queue:Peek() )

	for i = 1, 5 do
		Queue:Add( Data )
		Assert:Equals( i, Queue:GetCount() )
		Assert:Equals( Data, Queue:Peek() )
	end

	for i = 1, 3 do
		Assert:Equals( Data, Queue:Pop() )
		Assert:Equals( 5 - i, Queue:GetCount() )
	end

	for i = 1, 3 do
		Queue:Add( Data )
		Assert:Equals( i + 2, Queue:GetCount() )
		Assert:Equals( Data, Queue:Peek() )
	end

	for i = 1, 5 do
		Assert:Equals( Data, Queue:Pop() )
		Assert:Equals( 5 - i, Queue:GetCount() )
	end

	Assert:Nil( Queue:Peek() )
	Assert:Nil( Queue:Pop() )
end )
