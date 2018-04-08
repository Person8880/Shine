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

UnitTest:Test( "Pop", function( Assert )
	local Queue = Shine.Queue()
	for i = 1, 5 do
		Queue:Add( i )
	end

	for i = 1, 4 do
		Queue:Pop()

		local FirstValue = Queue:Peek()
		Assert:Equals( i + 1, FirstValue )
		Assert:Equals( 5 - i, Queue:GetCount() )
	end

	Queue:Pop()
	Assert:Nil( Queue:Peek() )
	Assert:Equals( 0, Queue:GetCount() )
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

	end
	Assert:Equals( 0, i )
end )

UnitTest:Test( "Add, then pop, then add", function( Assert )
	local Data = {}
	local Queue = Shine.Queue()

	Queue:Add( Data )
	Assert:Equals( 1, Queue:GetCount() )
	Assert:Equals( Data, Queue:Peek() )

	Queue:Pop()
	Assert:Equals( 0, Queue:GetCount() )
	Assert:Nil( Queue:Peek() )

	Queue:Add( Data )
	Assert:Equals( 1, Queue:GetCount() )
	Assert:Equals( Data, Queue:Peek() )
end )
