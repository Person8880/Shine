--[[
	Defines a simple set.
]]

local getmetatable = getmetatable
local TableGetKeys = table.GetKeys
local TableQuickCopy = table.QuickCopy
local TableShallowCopy = table.ShallowCopy

local Set = Shine.TypeDef()
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

function Set:ForEach( Consumer )
	return self.Stream:ForEach( Consumer )
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

	return self:Filter( Predicates.Has( Lookup ) )
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

function Set:Filter( Predicate )
	self.Stream:Filter( function( Value )
		local IsAllowed = Predicate( Value )
		if not IsAllowed then
			self.Lookup[ Value ] = nil
		end
		return IsAllowed
	end )
	return self
end

function Set:Add( Value )
	if not self.Lookup[ Value ] then
		self.Lookup[ Value ] = true
		self.List[ #self.List + 1 ] = Value
	end

	return self
end

function Set:Contains( Value )
	return self.Lookup[ Value ] or false
end

function Set:Remove( Value )
	return self:Filter( Predicates.Not( Predicates.Equals( Value ) ) )
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
