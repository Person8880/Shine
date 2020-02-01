--[[
	A simple queue structure.
]]

local TableEmpty = table.Empty

local Queue = Shine.TypeDef()
Shine.Queue = Queue

function Queue:Init()
	self.Size = 0
	self.Elements = {}
	self.First = 1
	self.Last = 0

	return self
end

function Queue:GetCount()
	return self.Size
end

function Queue:Add( Value )
	self.Last = self.Last + 1
	self.Elements[ self.Last ] = Value
	self.Size = self.Size + 1
end

function Queue:InsertAtFront( Value )
	self.First = self.First - 1
	self.Elements[ self.First ] = Value
	self.Size = self.Size + 1
end

function Queue:InsertAtIndex( Index, Value )
	local Elements = self.Elements
	local TargetIndex = self.First + Index - 1
	for i = self.Last, TargetIndex, -1 do
		Elements[ i + 1 ] = Elements[ i ]
	end

	Elements[ TargetIndex ] = Value

	self.Last = self.Last + 1
	self.Size = self.Size + 1
end

function Queue:InsertByComparing( Value, Comparator )
	local Elements = self.Elements

	for i = self.First, self.Last do
		if Comparator( Value, Elements[ i ] ) then
			return self:InsertAtIndex( i - self.First + 1, Value )
		end
	end

	return self:Add( Value )
end

-- Treats the queue as an array and filters out the given value.
do
	local function RemoveValue( Value, Index, ValueBeingRemoved )
		return Value ~= ValueBeingRemoved
	end

	function Queue:Remove( Value )
		return self:Filter( RemoveValue, Value )
	end
end

function Queue:Filter( Predicate, Context )
	local Elements = self.Elements
	local Offset = 0

	for i = self.First, self.Last do
		Elements[ i - Offset ] = Elements[ i ]
		if not Predicate( Elements[ i ], i, Context ) then
			Elements[ i ] = nil
			Offset = Offset + 1
			self.Size = self.Size - 1
		end
	end

	for i = self.Last, self.Last - Offset + 1, -1 do
		Elements[ i ] = nil
	end

	self.Last = self.Last - Offset

	return Offset ~= 0
end

function Queue:Pop()
	if self.Size == 0 then
		return nil
	end

	local Value = self.Elements[ self.First ]
	self.Elements[ self.First ] = nil

	self.First = self.First + 1
	self.Size = self.Size - 1

	if self.Size == 0 then
		-- Take the chance to reset the indices to avoid them growing
		-- extremely large.
		self.First = 1
		self.Last = 0
	end

	return Value
end

function Queue:Peek()
	return self.Elements[ self.First ]
end

function Queue:Get( Index )
	return self.Elements[ self.First + Index - 1 ]
end

function Queue:IndexOf( Value )
	local Elements = self.Elements

	for i = self.First, self.Last do
		if Value == Elements[ i ] then
			return i - self.First + 1
		end
	end

	return nil
end

function Queue:LastIndexOf( Value )
	local Elements = self.Elements

	for i = self.Last, self.First, -1 do
		if Value == Elements[ i ] then
			return i - self.First + 1
		end
	end

	return nil
end

function Queue:Clear()
	self.Size = 0
	self.First = 1
	self.Last = 0
	TableEmpty( self.Elements )
end

do
	local function Iterate( State )
		local Index = State.Index + 1
		State.Index = Index
		return State.Elements[ Index ]
	end

	function Queue:Iterate()
		return Iterate, { Elements = self.Elements, Index = self.First - 1 }
	end
end
