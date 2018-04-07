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
	self.Last = 1

	return self
end

function Queue:GetCount()
	return self.Size
end

function Queue:Add( Value )
	if self.Size == 0 then
		self.Elements[ self.First ] = Value
	else
		self.Last = self.Last + 1
		self.Elements[ self.Last ] = Value
	end

	self.Size = self.Size + 1
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
		self.Last = 1
	end

	return Value
end

function Queue:Peek()
	return self.Elements[ self.First ]
end

function Queue:Clear()
	self.Size = 0
	self.First = 1
	self.Last = 1
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
