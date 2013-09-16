--[[
	Shine debug library.
]]

local assert = assert
local DebugGetUpValue = debug.getupvalue
local StringFormat = string.format
local type = type

function Shine.GetUpValue( Func, Name )
	local i = 1
	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end

		if N == Name then
			return Val
		end
		i = i + 1
	end

	return nil
end

function Shine.IsType( Object, Type )
	return type( Object ) == Type
end

function Shine.Assert( Assertion, Error, ... )
	if not Assertion then
		error( StringFormat( Error, ... ), 2 )
	end
end
