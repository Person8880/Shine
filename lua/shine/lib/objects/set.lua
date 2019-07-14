--[[
	Defines a simple set.
]]

local getmetatable = getmetatable
local TableGetKeys = table.GetKeys
local TableQuickCopy = table.QuickCopy
local TableShallowCopy = table.ShallowCopy

local Set = Shine.TypeDef()

function Set.FromList( List )
	return Set():AddAll( List )
end

function Set:Init( Lookup )
	if getmetatable( Lookup ) == Set then
		self.List = TableQuickCopy( Lookup.List )
		self.Lookup = TableShallowCopy( Lookup.Lookup )
	else
		self.List = Lookup and TableGetKeys( Lookup ) or {}
		self.Lookup = Lookup and TableShallowCopy( Lookup ) or {}
	end

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
		if getmetatable( Lookup ) == Set then
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
			FilterOperation.Set.Lookup[ Value ] = nil
		end
		return IsAllowed
	end

	function Set:Filter( Predicate, Context )
		self.Stream:Filter( FilterValues, {
			Predicate = Predicate,
			Context = Context,
			Set = self
		} )
		return self
	end
end

function Set:Add( Value )
	if not self.Lookup[ Value ] then
		self.Lookup[ Value ] = true
		self.List[ #self.List + 1 ] = Value
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
		return self:Filter( IsNotValue, Value )
	end
end

function Set:GetCount()
	return #self.List
end

function Set:AsList()
	return self.List
end

function Set:__eq( OtherSet )
	if OtherSet:GetCount() ~= self:GetCount() then return false end

	-- We don't care about order, just that they're all present.
	for i = 1, #self.List do
		if not OtherSet:Contains( self.List[ i ] ) then
			return false
		end
	end

	return true
end

Shine.Set = Set
