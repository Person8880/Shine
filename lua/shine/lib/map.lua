--[[
	An iterable map, provides the speed of a numeric based loop
	while still allowing instant member checking and adding.
]]

local Clamp = math.Clamp
local rawset = rawset
local TableRemove = table.remove

local Map = {}
Map.__index = Map

setmetatable( Map, { __call = function( self )
	return setmetatable( {}, self ):Init()
end } )

function Shine.Map()
	return Map()
end

function Map:Init()
	self.Keys = {}
	self.MemberLookup = {}

	self.Position = 0
	self.NumMembers = 0

	return self
end

function Map:IsEmpty()
	return self.NumMembers == 0
end

function Map:GetCount()
	return self.NumMembers
end

--[[
	Adds a key-value pair to the map, or updates the value if it is already in it.

	Input: Key, value pair to map.
]]
function Map:Add( Key, Value )
	if Key == nil then return end

	if self.MemberLookup[ Key ] ~= nil then
		self.MemberLookup[ Key ] = Value

		return
	end

	local NumMembers = self.NumMembers + 1

	self.NumMembers = NumMembers

	self.Keys[ NumMembers ] = Key
	self.MemberLookup[ Key ] = Value
end

--[[
	Returns the value for the given key if it exists in the map.

	Input: Key.
	Output: Value mapped by the key or nil.
]]
function Map:Get( Key )
	return self.MemberLookup[ Key ]
end

--[[
	Removes a key from the map if it is mapped.

	Input: Key to remove.
	Output: The removed key, value pair if it existed in the map, otherwise nil.
]]
function Map:Remove( Key )
	if not self.MemberLookup[ Key ] then return nil end

	local Keys = self.Keys

	--Optimise removal if it's the current key.
	if Keys[ self.Position ] == Key then
		return self:RemoveAtPosition()
	end

	for i = 1, #Keys do
		local Member = Keys[ i ]

		if Member == Key then
			return self:RemoveAtPosition( i )
		end
	end

	return nil
end

--[[
	Removes a key, value pair at a specific position in the key Map.

	Input: Position, defaults to the current iteration position.
	Output: Removed key, value pair if it exists, or nil.
]]
function Map:RemoveAtPosition( Position )
	Position = Position or self.Position

	local Key = self.Keys[ Position ]
	if Key == nil then return nil end

	local Value = self.MemberLookup[ Key ]

	self.MemberLookup[ Key ] = nil
	TableRemove( self.Keys, Position )

	self.NumMembers = self.NumMembers - 1

	if self.Position >= Position then
		self.Position = self.Position - 1
	end

	return Key, Value
end

--[[
	Returns true if the map still has more elements to iterate through.

	Input:
	A boolean value to determine whether to reset the iteration position
	if there are no more values left.
]]
function Map:HasNext( DontReset )
	local Next = self.Keys[ self.Position + 1 ]

	if Next == nil then
		if not DontReset then
			self.Position = 0
		end

		return false
	end

	return true
end

--[[
	Returns true if the map has elements behind the current position.
]]
function Map:HasPrevious()
	return self.Position > 1 and self.NumMembers > 0
end

--[[
	Returns the next element if one exists, or nil otherwise.
	Advances the iteration position.
]]
function Map:GetNext()
	local InFront = self.Position + 1
	if InFront > self.NumMembers then
		return nil
	end

	self.Position = InFront

	local Key = self.Keys[ InFront ]

	return Key, self.MemberLookup[ Key ]
end

--[[
	Returns the next element if one exists, or nil otherwise.
	Does not advance the iteration position.
]]
function Map:PeekForward()
	local InFront = self.Position + 1
	if InFront > self.NumMembers then
		return nil
	end

	local Key = self.Keys[ InFront ]

	return Key, self.MemberLookup[ Key ]
end

--[[
	Returns the previous element if one exists, or nil otherwise.
	Moves the iteration position backwards.
]]
function Map:GetPrevious()
	local Behind = self.Position - 1
	if Behind <= 0 then
		return nil
	end

	self.Position = Behind

	local Key = self.Keys[ Behind ]

	return Key, self.MemberLookup[ Key ]
end

--[[
	Returns the previous element if one exists, or nil otherwise.
	Does not move the iteration position backwards.
]]
function Map:PeekBackwards()
	local Behind = self.Position - 1
	if Behind <= 0 then
		return nil
	end

	local Key = self.Keys[ Behind ]

	return Key, self.MemberLookup[ Key ]
end

--[[
	Resets the iteration position.
]]
function Map:ResetPosition()
	self.Position = 0
end

--[[
	Sets the iteration position.

	Input: New iteration position to jump to.
]]
function Map:SetPosition( Position )
	self.Position = Clamp( Position, 1, #self.Keys )
end

local GetNext = Map.GetNext
local GetPrevious = Map.GetPrevious

--If the map's empty, we don't even need to iterate.
local function Nope()
	return nil
end

--[[
	Iterator for the generic for loop.

	Avoids creating a new function, so is more JIT friendly than pairs.
]]
function Map:Iterate()
	self:ResetPosition()

	if self.NumMembers == 0 then
		return Nope
	end

	return GetNext, self
end

--[[
	Iterator for going backwards along the keys of the map.
]]
function Map:IterateBackwards()
	if self.NumMembers == 0 then
		return Nope
	end

	self.Position = self.NumMembers + 1

	return GetPrevious, self
end
