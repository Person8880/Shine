--[[
	Sets up and loads objects.
]]

local IsType = Shine.IsType
local getmetatable = getmetatable
local pairs = pairs
local setmetatable = setmetatable
local StringStartsWith = string.StartsWith

--[[
	Produces a meta-table that produces new instances by calling
	itself.

	On calling, the "Init" method will be invoked and be given all arguments
	from the call. It should return the instance.
]]
function Shine.TypeDef( Parent, Options )
	local MetaTable = {}
	MetaTable.__index = MetaTable

	if IsType( Options, "table" ) then
		-- Meta-methods are not resolved through __index, so they have to be copied if inheriting them is desired.
		if Parent and Options.InheritMetaMethods then
			for Key, Value in pairs( Parent ) do
				if IsType( Key, "string" ) and Key ~= "__index" and StringStartsWith( Key, "__" ) then
					MetaTable[ Key ] = Value
				end
			end
		end
	end

	return setmetatable( MetaTable, {
		__call = function( self, ... )
			return setmetatable( {}, self ):Init( ... )
		end,
		__index = Parent
	} )
end

--[[
	Tests whether the given value implements the given meta-table.
	This accounts for parents assigned in Shine.TypeDef().
]]
function Shine.Implements( Value, MetaTable )
	return Shine.IsAssignableTo( getmetatable( Value ), MetaTable )
end

function Shine.IsAssignableTo( MetaTable, Ancestor )
	local Parent = MetaTable
	while Parent and Parent ~= Ancestor do
		Parent = getmetatable( Parent )
		Parent = Parent and Parent.__index
	end
	return Parent == Ancestor
end

Shine.Objects = {}

Shine.LoadScriptsByPath( "lua/shine/lib/objects" )
