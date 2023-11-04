--[[
	An iterable map, provides the speed of a numeric based loop
	while still allowing constant time member checking and adding.
]]

local Clamp = math.Clamp
local Implements = Shine.Implements
local IsType = Shine.IsType
local pairs = pairs
local TableEmpty = table.Empty
local TableRemove = table.remove
local TableSort = table.sort
local TableMergeSort = table.MergeSort
local TableQuickRemove = table.QuickRemove
local TableShallowCopy = table.ShallowCopy

local Map = Shine.TypeDef()

Shine.Map = Map

function Map:Init( InitialValues )
	self.Keys = {}
	self.MemberLookup = {}

	self.Position = 0
	self.NumMembers = 0
	self.IterationDir = 1

	if IsType( InitialValues, "table" ) then
		if Implements( InitialValues, Map ) then
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
	if Comparator ~= nil then
		Shine.TypeCheck( Comparator, "function", 1, "SortKeys" )
	end
	return TableSort( self.Keys, Comparator )
end

function Map:StableSortKeys( Comparator )
	if Comparator ~= nil then
		Shine.TypeCheck( Comparator, "function", 1, "StableSortKeys" )
	end
	return TableMergeSort( self.Keys, Comparator )
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
	TableRemove( self.Keys, Position )

	self.NumMembers = self.NumMembers - 1

	if
		( self.Position >= Position and self.IterationDir == 1 ) or
		( self.Position > Position and self.IterationDir == -1 )
	then
		self.Position = self.Position - 1
	end

	return Key, Value
end

-- This is an internal method, used to implement filtering only.
function Map:RemoveKey( Index, Key )
	self.Keys[ Index ] = nil
	self.MemberLookup[ Key ] = nil
	self.NumMembers = self.NumMembers - 1
end

--[[
	Removes elements based on the given predicate, updating in-place.

	Inputs:
		1. Predicate - the predicate function, passed (Key, Value, Context).
		2. Context - optional context to pass into the predicate (to avoid the need for a closure).
	Output: This map, after it's been updated.
]]
function Map:Filter( Predicate, Context )
	local Keys = self.Keys
	local Size = self.NumMembers
	local Offset = 0
	local MemberLookup = self.MemberLookup

	for i = 1, Size do
		local Key = Keys[ i ]
		Keys[ i - Offset ] = Key
		if not Predicate( Key, MemberLookup[ Key ], Context ) then
			self:RemoveKey( i, Key )
			Offset = Offset + 1
		end
	end

	for i = Size, Size - Offset + 1, -1 do
		Keys[ i ] = nil
	end

	return self
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
	return self.Keys[ self.Position - 1 ] ~= nil
end

--[[
	Returns the next element if one exists, or nil otherwise.
	Advances the iteration position.
]]
function Map:GetNext()
	local InFront = self.Position + 1

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
	local Key = self.Keys[ InFront ]
	return Key, self.MemberLookup[ Key ]
end

--[[
	Returns the previous element if one exists, or nil otherwise.
	Moves the iteration position backwards.
]]
function Map:GetPrevious()
	local Behind = self.Position - 1

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
	self.Position = Clamp( Position, 1, self.NumMembers )
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
		self.IterationDir = 1

		return GetNext, self
	end

	--[[
		Iterator for going backwards along the keys of the map.
	]]
	function Map:IterateBackwards()
		self.Position = self.NumMembers + 1
		self.IterationDir = -1

		return GetPrevious, self
	end
end

function Map:__eq( OtherMap )
	if self:GetCount() ~= OtherMap:GetCount() then return false end

	for Key, Value in self:Iterate() do
		if OtherMap:Get( Key ) ~= Value then
			return false
		end
	end

	return true
end

--[[
	An unordered variant of Map that does not retain insertion order, but has constant time element removal.
]]
local UnorderedMap = Shine.TypeDef( Map, { InheritMetaMethods = true } )
Shine.UnorderedMap = UnorderedMap

function UnorderedMap:Init( InitialValues )
	self.IndexByKey = {}
	return Map.Init( self, InitialValues )
end

function UnorderedMap:Add( Key, Value )
	if Key == nil then return end

	if self.MemberLookup[ Key ] ~= nil then
		self.MemberLookup[ Key ] = Value
		return
	end

	local NumMembers = self.NumMembers + 1

	self.NumMembers = NumMembers
	self.Keys[ NumMembers ] = Key
	self.MemberLookup[ Key ] = Value
	self.IndexByKey[ Key ] = NumMembers
end

function UnorderedMap:Remove( Key )
	local Index = self.IndexByKey[ Key ]
	if not Index then return nil end

	local Size = self.NumMembers
	local Value = self.MemberLookup[ Key ]
	local KeyBeingMoved = self.Keys[ Size ]

	TableQuickRemove( self.Keys, Index, Size )

	self.NumMembers = Size - 1
	self.IndexByKey[ KeyBeingMoved ] = Index
	self.IndexByKey[ Key ] = nil
	self.MemberLookup[ Key ] = nil

	if Index == self.Position and self.IterationDir == 1 then
		self.Position = self.Position - 1
	end

	return Key, Value
end

function UnorderedMap:RemoveAtPosition( Position )
	Position = Position or self.Position

	local Key = self.Keys[ Position ]
	if Key == nil then return nil end

	return self:Remove( Key )
end

function UnorderedMap:RemoveKey( Index, Key )
	self.IndexByKey[ Key ] = nil
	return Map.RemoveKey( self, Index, Key )
end

function UnorderedMap:Clear()
	TableEmpty( self.IndexByKey )
	return Map.Clear( self )
end

--[[
	A multimap is a map that can map multiple values per key. It abstracts away the idiom of
	storing lists in a map structure.

	This implementation does not allow multiple instances of distinct key-value pairs. That is,
	you could not map key A to value B twice and have B show up twice in the value list for key A.
]]
local Multimap = Shine.TypeDef( Map )
Shine.Multimap = Multimap

local function InitMultimapFromValues( self, Values )
	if not Values then return self end

	if Implements( Values, Multimap ) then
		self:CopyFrom( Values )
	else
		for Key, List in pairs( Values ) do
			self:AddAll( Key, List )
		end
	end

	return self
end

--[[
	Initialises the multimap.

	If passed another multimap, it will copy all key-value pairs into this multimap.

	If passed a normal table, it will copy all key-value pairs under the assumption
	that all values are array-like.
]]
function Multimap:Init( Values )
	Map.Init( self )

	self.Count = 0

	return InitMultimapFromValues( self, Values )
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
	return self.NumMembers
end

--[[
	Adds a pair of values under the given key. The combination of the key and first value determine the uniquness of
	the entry, the second value will be overwritten.
]]
function Multimap:AddPair( Key, Value1, Value2 )
	local Entry = Map.Get( self, Key )
	if not Entry then
		Entry = Map()
		Map.Add( self, Key, Entry )

		self.Count = self.Count + 1
	elseif Entry:Get( Value1 ) == nil then
		self.Count = self.Count + 1
	end

	return Entry:Add( Value1, Value2 )
end

--[[
	Adds a new value under the given key if the given key-value pair has not been mapped already.
]]
function Multimap:Add( Key, Value )
	return self:AddPair( Key, Value, Value )
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
	-- Iterate the underlying map values, not just the keys.
	for Key, PairsMap in OtherMultimap:IteratePairs() do
		for Value1, Value2 in PairsMap:Iterate() do
			self:AddPair( Key, Value1, Value2 )
		end
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
	Returns a table with all values for the given key. Avoid modifying this table, or you will disrupt the multimap.
]]
function Multimap:Get( Key )
	local Entry = Map.Get( self, Key )
	if not Entry then return nil end

	return Entry.Keys
end

--[[
	Returns a map of all pairs stored under the given key. Avoid modifying this map.
]]
function Multimap:GetPairs( Key )
	return Map.Get( self, Key )
end

--[[
	Returns true if the given key-value is stored, false otherwise.
]]
function Multimap:HasKeyValue( Key, Value )
	return self:GetPairValue( Key, Value ) ~= nil
end

--[[
	Returns the second value associated with the given key-value, or nil if no such value is stored.
]]
function Multimap:GetPairValue( Key, Value )
	local Entry = Map.Get( self, Key )
	if not Entry then return nil end
	return Entry:Get( Value )
end

--[[
	Returns a table copy of the multimap as a standard Lua table of keys and table of values.

	Note that each table is directly linked to the multimap, so should not be edited.
]]
function Multimap:AsTable()
	local Table = {}
	for Key, List in self:Iterate() do
		Table[ Key ] = List
	end
	return Table
end

--[[
	Modify GetNext() and GetPrevious() to return the table of values under the key as the value, rather than the
	internal map holding them.
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
		self.IterationDir = 1

		return GetNext, self
	end

	-- Expose the original map iterator to iterate over pairs of values instead of lists.
	Multimap.IteratePairs = Map.Iterate
end

do
	local GetPrevious = Multimap.GetPrevious

	function Multimap:IterateBackwards()
		self.Position = self.NumMembers + 1
		self.IterationDir = -1

		return GetPrevious, self
	end

	Multimap.IteratePairsBackwards = Map.IterateBackwards
end

function Multimap:__eq( OtherMultimap )
	if self:GetCount() ~= OtherMultimap:GetCount() then return false end

	-- Check all value pairs, not just that the same key-values are stored.
	for Key, PairsMap in self:IteratePairs() do
		if OtherMultimap:GetPairs( Key ) ~= PairsMap then
			return false
		end
	end

	return true
end

--[[
	An unordered variant of Multimap that does not retain insertion order, but has constant time element removal.
]]
local UnorderedMultimap = Shine.TypeDef( Multimap, { InheritMetaMethods = true } )
Shine.UnorderedMultimap = UnorderedMultimap

function UnorderedMultimap:Init( Values )
	UnorderedMap.Init( self )

	self.Count = 0

	return InitMultimapFromValues( self, Values )
end

function UnorderedMultimap:Clear()
	UnorderedMap.Clear( self )
	self.Count = 0
end

function UnorderedMultimap:AddPair( Key, Value1, Value2 )
	local Entry = Map.Get( self, Key )
	if not Entry then
		Entry = UnorderedMap()
		UnorderedMap.Add( self, Key, Entry )

		self.Count = self.Count + 1
	elseif Entry:Get( Value1 ) == nil then
		self.Count = self.Count + 1
	end

	return Entry:Add( Value1, Value2 )
end

function UnorderedMultimap:RemoveKeyValue( Key, Value )
	local Entry = Map.Get( self, Key )
	if not Entry then return end

	local Removed = Entry:Remove( Value ) ~= nil
	if Removed then
		self.Count = self.Count - 1

		if Entry:GetCount() == 0 then
			UnorderedMap.Remove( self, Key )
		end
	end

	return Removed
end
