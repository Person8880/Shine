--[[
	Queue object unit tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Add", function( Assert )
	local Queue = Shine.Queue()
	Queue:Add( 1 )

	local FirstNode = Queue.FirstNode
	Assert:NotNil( FirstNode )
	Assert:Nil( FirstNode.Previous )
	Assert:Nil( FirstNode.Next )
	Assert:Equals( FirstNode, Queue.LastNode )
	Assert:Equals( 1, FirstNode.Value )
	Assert:Equals( 1, Queue:GetCount() )

	Queue:Add( 2 )
	Assert:Equals( FirstNode, Queue.FirstNode )
	Assert:NotNil( FirstNode.Next )
	Assert:Equals( FirstNode.Next.Previous, FirstNode )
	Assert:Nil( FirstNode.Next.Next )
	Assert:Equals( FirstNode.Next, Queue.LastNode )
	Assert:Equals( 2, FirstNode.Next.Value )
	Assert:Equals( 2, Queue:GetCount() )
end )

UnitTest:Test( "Pop", function( Assert )
	local Queue = Shine.Queue()
	for i = 1, 5 do
		Queue:Add( i )
	end

	for i = 1, 4 do
		Queue:Pop()

		local FirstNode = Queue.FirstNode
		Assert:NotNil( FirstNode )
		Assert:Nil( FirstNode.Previous )
		Assert:Equals( i + 1, FirstNode.Value )
		Assert:Equals( 5 - i, Queue:GetCount() )
	end

	Queue:Pop()
	Assert:Nil( Queue.FirstNode )
	Assert:Nil( Queue.LastNode )
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
	Assert:Equals( Data, Queue.FirstNode.Value )
	Assert:Equals( Data, Queue.LastNode.Value )

	-- Popping should clear both the first and last node on the last pop.
	Queue:Pop()
	Assert:Equals( 0, Queue:GetCount() )
	Assert:Nil( Queue.FirstNode )
	Assert:Nil( Queue.LastNode )

	Queue:Add( Data )
	Assert:Equals( 1, Queue:GetCount() )
	Assert:Equals( Data, Queue.FirstNode.Value )
	Assert:Equals( Data, Queue.LastNode.Value )
end )
