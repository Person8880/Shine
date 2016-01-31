--[[
	Sets up and loads objects.
]]

local setmetatable = setmetatable

function Shine.TypeDef( Parent )
	local MetaTable = {}
	MetaTable.__index = MetaTable

	return setmetatable( MetaTable, {
		__call = function( self, ... )
			return setmetatable( {}, self ):Init( ... )
		end,
		__index = Parent
	} )
end

Shine.LoadScriptsByPath( "lua/shine/lib/objects" )
