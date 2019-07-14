--[[
	Linked list unit tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Add", function( Assert )
	local List = Shine.LinkedList()
	local Node = List:Add( 1 )

	Assert.Equals( "Node should have correct value", 1, Node.Value )
	Assert.Nil( "Node should have no next node", Node.Next )
	Assert.Nil( "Node should have no previous node", Node.Prev )
	Assert.Equals( "Node should be the first", List.First, Node )
	Assert.Equals( "Node should be the last", List.Last, Node )
	Assert.Equals( "List should have size 1", 1, List:GetCount() )

	local SecondNode = List:Add( 2 )

	Assert.Equals( "Second node should have correct value", 2, SecondNode.Value )
	Assert.Equals( "First node should be behind second", Node, SecondNode.Prev )
	Assert.Equals( "Second node should be in front of first", SecondNode, Node.Next )
	Assert.Equals( "First node should be first", Node, List.First )
	Assert.Equals( "Second node should be last", SecondNode, List.Last )
	Assert.Nil( "Second node should have no next node", SecondNode.Next )
	Assert.Nil( "First node should have no previous node", Node.Prev )
	Assert.Equals( "List should have size 2", 2, List:GetCount() )
end )

UnitTest:Test( "InsertAtFront", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	local Node = List:InsertAtFront( 0 )
	Assert.Equals( "Node should have correct value", 0, Node.Value )
	Assert.Equals( "Node's next node should be the previous first", Nodes[ 1 ], Node.Next )
	Assert.Equals( "Previous first node should have new node as previous", Node, Nodes[ 1 ].Prev )
	Assert.Equals( "Node should be first", Node, List.First )
	Assert.Nil( "Node should have no previous node", Node.Prev )
end )

UnitTest:Test( "InsertAfter mid-list", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	local Node = List:InsertAfter( Nodes[ 2 ], 0 )
	Assert.Equals( "Node should have correct value", 0, Node.Value )
	Assert.Equals( "Node's next node should be the previous third", Nodes[ 3 ], Node.Next )
	Assert.Equals( "Node's previous node should be the previous second", Nodes[ 2 ], Node.Prev )
	Assert.Equals( "Node should be behind the third node", Node, Nodes[ 3 ].Prev )
	Assert.Equals( "Node should be in front of the second node", Node, Nodes[ 2 ].Next )
	Assert.Equals( "Last node should be unchanged", Nodes[ 5 ], List.Last )
	Assert.Equals( "List should have size 6", 6, List:GetCount() )
end )

UnitTest:Test( "InsertAfter at end of list", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	local Node = List:InsertAfter( Nodes[ 5 ], 0 )
	Assert.Equals( "Node should have correct value", 0, Node.Value )
	Assert.Equals( "Node 5's next node be the new node", Node, Nodes[ 5 ].Next )
	Assert.Equals( "Node's previous node should be the fifth", Nodes[ 5 ], Node.Prev )
	Assert.Nil( "Node should have no next node", Node.Next )
	Assert.Equals( "Last node should be the new node", Node, List.Last )
	Assert.Equals( "List should have size 6", 6, List:GetCount() )
end )

UnitTest:Test( "InsertByComparing - start of list", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	local Node = List:InsertByComparing( 0, function( A, B ) return A < B end )
	Assert.Equals( "Node should have correct value", 0, Node.Value )
	Assert.Equals( "Node's next node should be the previous first", Nodes[ 1 ], Node.Next )
	Assert.Nil( "Node should have no previous node", Node.Prev )
	Assert.Equals( "Node should be behind the first node", Node, Nodes[ 1 ].Prev )
	Assert.Equals( "Node should be the new first node", Node, List.First )
	Assert.Equals( "Last node should be unchanged", Nodes[ 5 ], List.Last )
	Assert.Equals( "List should have size 6", 6, List:GetCount() )
end )

UnitTest:Test( "InsertByComparing - mid-list", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	local Node = List:InsertByComparing( 3, function( A, B ) return A < B end )
	Assert.Equals( "Node should have correct value", 3, Node.Value )
	Assert.Equals( "Node's next node should be the previous fourth", Nodes[ 4 ], Node.Next )
	Assert.Equals( "Node's previous node should be the previous third", Nodes[ 3 ], Node.Prev )
	Assert.Equals( "Node should be behind the fourth node", Node, Nodes[ 4 ].Prev )
	Assert.Equals( "Node should be in front of the third node", Node, Nodes[ 3 ].Next )
	Assert.Equals( "First node should be unchanged", Nodes[ 1 ], List.First )
	Assert.Equals( "Last node should be unchanged", Nodes[ 5 ], List.Last )
	Assert.Equals( "List should have size 6", 6, List:GetCount() )
end )

UnitTest:Test( "InsertByComparing - end of list", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	local Node = List:InsertByComparing( 6, function( A, B ) return A < B end )
	Assert.Equals( "Node should have correct value", 6, Node.Value )
	Assert.Equals( "Node 5's next node be the new node", Node, Nodes[ 5 ].Next )
	Assert.Equals( "Node's previous node should be the fifth", Nodes[ 5 ], Node.Prev )
	Assert.Nil( "Node should have no next node", Node.Next )
	Assert.Equals( "First node should be unchanged", Nodes[ 1 ], List.First )
	Assert.Equals( "Last node should be the new node", Node, List.Last )
	Assert.Equals( "List should have size 6", 6, List:GetCount() )
end )

UnitTest:Test( "Remove only element", function( Assert )
	local List = Shine.LinkedList()
	local Node = List:Add( 1 )

	Assert.Equals( "List should have size 1", 1, List:GetCount() )

	List:Remove( Node )

	Assert.Nil( "List should have no first node", List.First )
	Assert.Nil( "List should have no last node", List.Last )

	Assert.Equals( "List should have size 0", 0, List:GetCount() )
end )

UnitTest:Test( "Remove start of list", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	List:Remove( Nodes[ 1 ] )

	Assert.Equals( "Second node should now be first", Nodes[ 2 ], List.First )
	Assert.Equals( "Fifth node should still be last", Nodes[ 5 ], List.Last )
	Assert.Nil( "Second node should have no previous node", Nodes[ 2 ].Prev )
	Assert.Equals( "List should have size 4", 4, List:GetCount() )
end )

UnitTest:Test( "Remove mid-list", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	List:Remove( Nodes[ 3 ] )

	Assert.Equals( "First node should still be first", Nodes[ 1 ], List.First )
	Assert.Equals( "Fifth node should still be last", Nodes[ 5 ], List.Last )
	Assert.Equals( "Second node should have fourth as next node", Nodes[ 4 ], Nodes[ 2 ].Next )
	Assert.Equals( "Fourth node should have second as previous ndoe", Nodes[ 2 ], Nodes[ 4 ].Prev )
	Assert.Equals( "List should have size 4", 4, List:GetCount() )
end )

UnitTest:Test( "Clear", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	Assert.Equals( "List should have size 5", 5, List:GetCount() )

	List:Clear()

	Assert.Nil( "List should have no first node", List.First )
	Assert.Nil( "List should have no last node", List.Last )

	Assert.Equals( "List should have size 0", 0, List:GetCount() )
end )

UnitTest:Test( "Iterate", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	local i = 0
	for Value in List:Iterate() do
		i = i + 1
		Assert:Equals( i, Value )
	end
	Assert.Equals( "Iteration didn't iterate all values", 5, i )
end )

UnitTest:Test( "Iterate and remove", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	local i = 0
	for Value in List:Iterate() do
		i = i + 1
		Assert:Equals( i, Value )
		-- Node still points at next node, so iteration should be unaffected.
		List:Remove( Nodes[ i ] )
	end

	Assert.Equals( "Iteration didn't iterate all values", 5, i )
	Assert.Equals( "List should be empty after iteration", 0, List:GetCount() )
end )

UnitTest:Test( "IterateNodes", function( Assert )
	local List = Shine.LinkedList()
	local Nodes = {}
	for i = 1, 5 do
		Nodes[ i ] = List:Add( i )
	end

	local i = 0
	for Node in List:IterateNodes() do
		i = i + 1
		Assert:Equals( i, Node.Value )
	end
	Assert.Equals( "Iteration didn't iterate all values", 5, i )
end )

UnitTest:Test( "IterateNodes when empty", function( Assert )
	local List = Shine.LinkedList()
	local i = 0
	for Node in List:IterateNodes() do
		i = i + 1
	end
	Assert.Equals( "Should not have iterated over any nodes", 0, i )
end )
