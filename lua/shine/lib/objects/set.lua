--[[
	Defines a simple set.
]]

local Implements = Shine.Implements
local TableAsSet = table.AsSet
local TableEmpty = table.Empty
local TableGetKeys = table.GetKeys
local TableQuickCopy = table.QuickCopy
local TableQuickRemove = table.QuickRemove
local TableRemove = table.remove
local TableShallowCopy = table.ShallowCopy

local Set = Shine.TypeDef()

function Set.FromList( List )
	return Set():AddAll( List )
end

function Set:Init( Lookup )
	if Implements( Lookup, Set ) then
		self.List = TableQuickCopy( Lookup.List )
		self.Lookup = TableShallowCopy( Lookup.Lookup )
	else
		self.List = Lookup and TableGetKeys( Lookup ) or {}
		self.Lookup = Lookup and TableShallowCopy( Lookup ) or {}
	end

	self.Count = #self.List
	self.Stream = Shine.Stream( self.List )

	return self
end

do
	local function Iterate( Context )
		Context.Index = Context.Index + 1
		return Context.List[ Context.Index ]
	end

	function Set:Iterate()
		return Iterate, { List = self.List, Index = 0 }
	end

	local function IterateBackwards( Context )
		Context.Index = Context.Index - 1
		return Context.List[ Context.Index ]
	end

	function Set:IterateBackwards()
		return IterateBackwards, { List = self.List, Index = self.Count + 1 }
	end
end

function Set:ForEach( Consumer, Context )
	return self.Stream:ForEach( Consumer, Context )
end

do
	local function LookupContainsValue( Value, Lookup )
		return Lookup[ Value ]
	end

	--[[
		Removes all elements not contained in the given lookup set.

		This can either be a set instance, or a normal Lua table whose keys are the
		values to be kept.
	]]
	function Set:Intersection( Lookup )
		if Implements( Lookup, Set ) then
			Lookup = Lookup.Lookup
		end

		return self:Filter( LookupContainsValue, Lookup )
	end
end

--[[
	Adds all elements from the given set to this one.
]]
function Set:Union( OtherSet )
	for Value in OtherSet:Iterate() do
		self:Add( Value )
	end

	return self
end

do
	local function FilterValues( Value, Index, FilterOperation )
		local IsAllowed = FilterOperation.Predicate( Value, FilterOperation.Context )
		if not IsAllowed then
			FilterOperation.Lookup[ Value ] = nil
			FilterOperation.Count = FilterOperation.Count - 1
		end
		return IsAllowed
	end

	local FilterOperation = {}
	function Set:Filter( Predicate, Context )
		FilterOperation.Predicate = Predicate
		FilterOperation.Context = Context
		FilterOperation.Lookup = self.Lookup
		FilterOperation.Count = self.Count

		self.Stream:Filter( FilterValues, FilterOperation )
		self.Count = FilterOperation.Count

		return self
	end
end

function Set:Add( Value )
	if not self.Lookup[ Value ] then
		local Index = self.Count + 1
		self.Lookup[ Value ] = true
		self.List[ Index ] = Value
		self.Count = Index
	end

	return self
end

function Set:AddAll( Values )
	for i = 1, #Values do
		self:Add( Values[ i ] )
	end
	return self
end

function Set:ReplaceMatchingValue( ValueToAdd, Predicate, Context )
	for i = 1, #self.List do
		local Value = self.List[ i ]
		if Predicate( Value, i, Context ) then
			self.List[ i ] = ValueToAdd

			self.Lookup[ Value ] = nil
			self.Lookup[ ValueToAdd ] = true

			break
		end
	end
	return self
end

function Set:Contains( Value )
	return not not self.Lookup[ Value ]
end

do
	local function IsNotValue( Value, ValueToRemove )
		return Value ~= ValueToRemove
	end

	function Set:Remove( Value )
		if not self:Contains( Value ) then return self end

		for i = 1, self.Count do
			if self.List[ i ] == Value then
				self.Lookup[ Value ] = nil
				self.Count = self.Count - 1

				TableRemove( self.List, i )

				break
			end
		end

		return self
	end
end

do
	local function NotInLookup( Value, Lookup )
		return not Lookup[ Value ]
	end

	function Set:RemoveAll( Values )
		if #Values == 0 then return self end

		return self:Filter( NotInLookup, TableAsSet( Values ) )
	end
end

function Set:Clear()
	TableEmpty( self.List )
	TableEmpty( self.Lookup )
	self.Count = 0
	return self
end

function Set:GetCount()
	return self.Count
end

function Set:AsList()
	return self.List
end

Set.__len = Set.GetCount

function Set:__eq( OtherSet )
	local OurSize = self:GetCount()
	if OtherSet:GetCount() ~= OurSize then return false end

	-- We don't care about order, just that they're all present.
	for i = 1, OurSize do
		if not OtherSet:Contains( self.List[ i ] ) then
			return false
		end
	end

	return true
end

Shine.Set = Set

-- Unordered variation of Set that does not maintain insertion order, but benefits from faster element removal.
local UnorderedSet = Shine.TypeDef( Set, {
	InheritMetaMethods = true
} )

function UnorderedSet.FromList( List )
	return UnorderedSet():AddAll( List )
end

function UnorderedSet:Add( Value )
	if not self.Lookup[ Value ] then
		local Index = self.Count + 1
		self.Lookup[ Value ] = Index
		self.List[ Index ] = Value
		self.Count = Index
	end

	return self
end

function UnorderedSet:Remove( Value )
	local Index = self.Lookup[ Value ]
	if Index then
		local Size = self.Count
		local ValueBeingMoved = self.List[ Size ]

		TableQuickRemove( self.List, Index, Size )

		self.Lookup[ ValueBeingMoved ] = Index
		self.Lookup[ Value ] = nil
		self.Count = Size - 1
	end

	return self
end

do
	local function FilterValues( Value, Index, FilterOperation )
		local IsAllowed = FilterOperation.Predicate( Value, FilterOperation.Context )

		if not IsAllowed then
			FilterOperation.Offset = FilterOperation.Offset + 1
			FilterOperation.Lookup[ Value ] = nil
			FilterOperation.Count = FilterOperation.Count - 1
		else
			-- Update the index of each retained value as they may move down during the filter operation.
			FilterOperation.Lookup[ Value ] = Index - FilterOperation.Offset
		end

		return IsAllowed
	end

	local FilterOperation = {}
	function UnorderedSet:Filter( Predicate, Context )
		FilterOperation.Predicate = Predicate
		FilterOperation.Context = Context
		FilterOperation.Lookup = self.Lookup
		FilterOperation.Count = self.Count
		FilterOperation.Offset = 0

		self.Stream:Filter( FilterValues, FilterOperation )
		self.Count = FilterOperation.Count

		return self
	end
end

function UnorderedSet:ReplaceMatchingValue( ValueToAdd, Predicate, Context )
	for i = 1, #self.List do
		local Value = self.List[ i ]
		if Predicate( Value, i, Context ) then
			self.List[ i ] = ValueToAdd

			self.Lookup[ Value ] = nil
			self.Lookup[ ValueToAdd ] = i

			break
		end
	end
	return self
end

Shine.UnorderedSet = UnorderedSet
