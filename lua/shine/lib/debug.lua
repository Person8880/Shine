--[[
	Shine debug library.
]]

local assert = assert
local DebugGetUpValue = debug.getupvalue
local DebugSetUpValue = debug.setupvalue
local StringFormat = string.format
local type = type

--[[
	Gets an upvalue from the given function.

	Inputs:
		1. Function to get the upvalue from.
		2. Name of the upvalue variable.
	Output:
		Upvalue or nil if not found.
]]
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

--[[
	Sets an upvalue for the given function.

	Inputs:
		1. Function to set the upvalue for.
		2. Name of the upvalue variable.
		3. New value to set as the upvalue's value.
	Output:
		Old value on success, or nil on failure.
]]
function Shine.SetUpValue( Func, Name, Value )
	local i = 1

	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end
		
		if N == Name then
			DebugSetUpValue( Func, i, Value )

			return Val
		end

		i = i + 1
	end

	return nil
end

--[[
	Checks a given object's type.

	Inputs:
		1. Object to check.
		2. Type to check against.
	Output:
		True if the object has the given type.
]]
function Shine.IsType( Object, Type )
	return type( Object ) == Type
end

--[[
	Asserts a condition and formats the error message.

	Inputs:
		1. Assertion condition.
		2. Error message.
		3. Format arguments for the error message.
]]
function Shine.Assert( Assertion, Error, ... )
	if not Assertion then
		error( StringFormat( Error, ... ), 2 )
	end
end
