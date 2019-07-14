--[[
	A doubly-linked list.
]]

local LinkedList = Shine.TypeDef()
Shine.LinkedList = LinkedList

function LinkedList:Init()
	self.Size = 0

	return self
end

local function MakeNode( Value )
	return {
		Value = Value
	}
end


-- Adds a value to the end of the linked list.
-- Returns the added node.
function LinkedList:Add( Value )
	local Node = MakeNode( Value )

	if not self.First then
		self.First = Node
	end

	if self.Last then
		Node.Prev = self.Last
		self.Last.Next = Node
	end

	self.Last = Node
	self.Size = self.Size + 1

	return Node
end

-- Inserts a value at the front of the list.
-- Returns the added node.
function LinkedList:InsertAtFront( Value )
	local NewNode = MakeNode( Value )
	if self.First then
		NewNode.Next = self.First
		self.First.Prev = NewNode
	end

	self.First = NewNode
	self.Size = self.Size + 1

	return NewNode
end

-- Inserts a value after the given node.
-- Returns the added node.
function LinkedList:InsertAfter( Node, Value )
	if not Node then
		return self:InsertAtFront( Value )
	end

	local NewNode = MakeNode( Value )

	NewNode.Next = Node.Next
	NewNode.Prev = Node

	if Node.Next then
		Node.Next.Prev = NewNode
	else
		self.Last = NewNode
	end

	Node.Next = NewNode

	self.Size = self.Size + 1

	return NewNode
end

-- Inserts the given value after the last value in the list that is
-- considered less than or equal to the given value using the given comparator.
function LinkedList:InsertByComparing( Value, Comparator )
	for Node in self:IterateNodes() do
		if Comparator( Value, Node.Value ) then
			return self:InsertAfter( Node.Prev, Value )
		end
	end

	return self:Add( Value )
end

-- Removes the given node from the linked list.
-- This assumes the node is part of the list.
function LinkedList:Remove( Node )
	if self.First == Node then
		self.First = Node.Next

		if self.First then
			self.First.Prev = nil
		end
	else
		Node.Prev.Next = Node.Next
		if Node.Next then
			Node.Next.Prev = Node.Prev
		end
	end

	if Node == self.Last then
		self.Last = Node.Prev
	end

	self.Size = self.Size - 1
end

-- Clears all values from the linked list.
function LinkedList:Clear()
	self.First = nil
	self.Last = nil
	self.Size = 0
end

-- Gets the number of elements in the linked list.
function LinkedList:GetCount()
	return self.Size
end

local function Iterate( State )
	local Next = State.Node and State.Node.Next
	if not Next then return nil end

	State.Node = Next

	return Next.Value
end

-- Iterates the values in the linked list.
function LinkedList:Iterate()
	return Iterate, { Node = { Next = self.First } }
end

local function IterateNodes( List, PrevNode )
	return PrevNode.Next
end

-- Iterates the nodes in the linked list.
function LinkedList:IterateNodes()
	return IterateNodes, self, { Next = self.First }
end
