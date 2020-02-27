--[[
	An iterable map, provides the speed of a numeric based loop
	while still allowing constant time member checking and adding.
]]

local Clamp = math.Clamp
local getmetatable = getmetatable
local IsType = Shine.IsType
local pairs = pairs
local TableEmpty = table.Empty
local TableSort = table.sort
local TableMergeSort = table.MergeSort
local TableShallowCopy = table.ShallowCopy

local Map = Shine.TypeDef()

Shine.Map = Map

function Map:Init( InitialValues )
	self.Keys = {}
	self.MemberLookup = {}

	self.Position = 0
	self.NumMembers = 0

	if IsType( InitialValues, "table" ) then
		if getmetatable( InitialValues ) == Map then
			for Key, Value in InitialValues:Iterate() do
				self:Add( Key, Value )
			end
		else
			for Key, Value in pairs( InitialValues ) do
				self:Add( Key, Value )
			end
		end
	end

	return self
end

function Map:Clear()
	TableEmpty( self.Keys )
	TableEmpty( self.MemberLookup )

	self.Position = 0
	self.NumMembers = 0
end

function Map:IsEmpty()
	return self.NumMembers == 0
end

function Map:GetCount()
	return self.NumMembers
end

function Map:GetKeys()
	return self.Keys
end

function Map:AsTable()
	return TableShallowCopy( self.MemberLookup )
end

function Map:SortKeys( Comparator )
	Shine.TypeCheck( Comparator, "function", 1, "SortKeys" )
	TableSort( self.Keys, Comparator )
end

function Map:StableSortKeys( Comparator )
	Shine.TypeCheck( Comparator, "function", 1, "StableSortKeys" )
	TableMergeSort( self.Keys, Comparator )
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
	if self.MemberLookup[ Key ] == nil then return nil end

	local Keys = self.Keys

	-- Optimise removal if it's the current key.
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
	for i = Position, #self.Keys do
		self.Keys[ i ] = self.Keys[ i + 1 ]
	end

	self.NumMembers = self.NumMembers - 1

	if self.Position >= Position then
		self.Position = self.Position - 1
	end

	return Key, Value
end

--[[
	Returns true if the map still has more elements to iterate through.
]]
function Map:HasNext()
	return self.Keys[ self.Position + 1 ] ~= nil
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

do
	local GetNext = Map.GetNext
	local GetPrevious = Map.GetPrevious

	--[[
		Iterator for the generic for loop.

		Avoids creating a new function, so is more JIT friendly than pairs.
	]]
	function Map:Iterate()
		self.Position = 0

		return GetNext, self
	end

	--[[
		Iterator for going backwards along the keys of the map.
	]]
	function Map:IterateBackwards()
		self.Position = self.NumMembers + 1

		return GetPrevious, self
	end
end

--[[
	A multimap is a map that can map multiple values per key. It abstracts away the idiom of
	storing lists in a map structure.

	This implementation does not allow multiple instances of distinct key-value pairs. That is,
	you could not map key A to value B twice and have B show up twice in the value list for key A.
]]
local Multimap = Shine.TypeDef( Map )
Shine.Multimap = Multimap

--[[
	Initialises the multimap.

	If passed another multimap, it will copy all key-value pairs into this multimap.

	If passed a normal table, it will copy all key-value pairs under the assumption
	that all values are array-like.
]]
function Multimap:Init( Values )
	Map.Init( self )

	self.Count = 0

	if not Values then return self end

	if getmetatable( Values ) == Multimap then
		for Key, List in Values:Iterate() do
			for i = 1, #List do
				self:Add( Key, List[ i ] )
			end
		end

		return self
	end

	for Key, List in pairs( Values ) do
		for i = 1, #List do
			self:Add( Key, List[ i ] )
		end
	end

	return self
end

function Multimap:Clear()
	Map.Clear( self )
	self.Count = 0
end

--[[
	Returns the number of distinct key-value pairs in the multimap,
	not the number of keys.
]]
function Multimap:GetCount()
	return self.Count
end

function Multimap:GetKeyCount()
	return #self.Keys
end

--[[
	Adds a new value under the given key if the given key-value pair has not
	been mapped already.
]]
function Multimap:Add( Key, Value )
	local Entry = Map.Get( self, Key )
	if not Entry then
		Entry = Map()
		Map.Add( self, Key, Entry )

		self.Count = self.Count + 1
	elseif Entry:Get( Value ) == nil then
		self.Count = self.Count + 1
	end

	Entry:Add( Value, Value )
end

--[[
	Adds a list of values under the given key.
]]
function Multimap:AddAll( Key, Values )
	for i = 1, #Values do
		self:Add( Key, Values[ i ] )
	end
end

--[[
	Copies all values from the given multimap into this one.
]]
function Multimap:CopyFrom( OtherMultimap )
	for Key, Values in OtherMultimap:Iterate() do
		self:AddAll( Key, Values )
	end
end

--[[
	Removes a key-value pair from the multimap, if it exists. Returns true if the
	given pair was found and removed, false otherwise.
]]
function Multimap:RemoveKeyValue( Key, Value )
	local Entry = Map.Get( self, Key )
	if not Entry then return end

	local Removed = Entry:Remove( Value ) ~= nil
	if Removed then
		self.Count = self.Count - 1

		if Entry:GetCount() == 0 then
			Map.Remove( self, Key )
		end
	end

	return Removed
end

--[[
	Returns a table with all values for the given key. Avoid modifying this table,
	or you will disrupt the multimap.
]]
function Multimap:Get( Key )
	local Entry = Map.Get( self, Key )
	if not Entry then return nil end

	return Entry.Keys
end

--[[
	Returns a table copy of the multimap as a standard Lua table of keys and
	table of values. Note that each table is directly linked to the multimap, so
	should not be edited.
]]
function Multimap:AsTable()
	local Table = {}
	for Key, List in self:Iterate() do
		Table[ Key ] = List
	end
	return Table
end

--[[
	Modify GetNext() and GetPrevious() to return the table of values under the key
	as the value, rather than the internal map holding them.
]]
function Multimap:GetNext()
	local Key, Values = Map.GetNext( self )
	if Key ~= nil then
		return Key, Values.Keys
	end

	return nil
end

function Multimap:GetPrevious()
	local Key, Values = Map.GetPrevious( self )
	if Key ~= nil then
		return Key, Values.Keys
	end

	return nil
end

--[[
	Modify iterators to make use of the modified GetNext()/GetPrevious().
]]
do
	local GetNext = Multimap.GetNext

	function Multimap:Iterate()
		self.Position = 0

		return GetNext, self
	end
end

do
	local GetPrevious = Multimap.GetPrevious

	function Multimap:IterateBackwards()
		self.Position = self.NumMembers + 1

		return GetPrevious, self
	end
end
