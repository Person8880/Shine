--[[
	A simple linked queue structure.
]]

local Queue = {}
Queue.__index = Queue

do
	local setmetatable = setmetatable

	function Shine.Queue()
		return setmetatable( {}, Queue ):Init()
	end
end

function Queue:Init()
	self.Size = 0
	self.Nodes = {}

	return self
end

function Queue:GetCount()
	return self.Size
end

function Queue:Add( Value )
	local Previous = self.LastNode
	local Next = {
		Value = Value,
		Previous = Previous
	}

	self.Nodes[ Next ] = Next

	if Previous then
		Previous.Next = Next
	else
		self.FirstNode = Next
	end

	self.LastNode = Next
	self.Size = self.Size + 1
end

function Queue:Pop()
	if self.Size == 0 then
		return nil
	end

	local Node = self.FirstNode
	self.Nodes[ Node ] = nil

	if Node.Next then
		Node.Next.Previous = nil
	end

	self.Size = self.Size - 1
	self.FirstNode = Node.Next

	return Node.Value
end

function Queue:Peek()
	return self.FirstNode and self.FirstNode.Value
end

function Queue:HasNext()
	return ( self.CurrentNode and self.CurrentNode.Next or self.FirstNode ) ~= nil
end

function Queue:GetNext()
	if not self.CurrentNode then return nil end

	local Value = self.CurrentNode.Value
	self.CurrentNode = self.CurrentNode.Next

	return Value
end

do
	local GetNext = Queue.GetNext
	local function Nope() end

	function Queue:Iterate()
		if self.Size == 0 then return Nope end

		self.CurrentNode = self.FirstNode

		return GetNext, self
	end
end

-- Avoid this, because it's not really how you should use a queue.
function Queue:Remove( Node )
	if not self.Nodes[ Node ] then return end

	if Node.Previous then
		Node.Previous.Next = Node.Next
	end

	if Node.Next then
		Node.Next.Previous = Node.Previous
	end

	if self.CurrentNode == Node then
		self.CurrentNode = Node.Previous
	end

	if self.FirstNode == Node then
		self.FirstNode = Node.Next
	end

	if self.LastNode == Node then
		self.LastNode = Node.Previous
	end

	self.Size = self.Size - 1
	self.Nodes[ Node ] = nil
end
