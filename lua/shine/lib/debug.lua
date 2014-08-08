--[[
	Shine debug library.
]]

local assert = assert
local DebugGetLocal = debug.getlocal
local DebugGetUpValue = debug.getupvalue
local DebugSetUpValue = debug.setupvalue
local pairs = pairs
local StringFormat = string.format
local type = type

--[[
	Gets an upvalue from the given function.

	Inputs:
		1. Function to get the upvalue from.
		2. Name of the upvalue variable.
	Outputs:
		1. Upvalue or nil if not found.
		2. Index at which the upvalue was found.
		3. Function the upvalue was found first in,
		   or nil if it was found in the input function.
]]
function Shine.GetUpValue( Func, Name, Recursive, Done )
	local i = 1
	--Avoid upvalue cycles (it is possible.)
	Done = Done or {}
	if Done[ Func ] then return nil end
	
	Done[ Func ] = true

	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end

		if N == Name then
			return Val, i
		elseif Recursive and not Done[ Val ] and type( Val ) == "function" then
			local LowerVal, j, Function = Shine.GetUpValue( Val, Name, true, Done )

			if LowerVal then
				return LowerVal, j, Function or Val
			end
		end

		i = i + 1
	end

	return nil
end

--[[
	Returns a table containing every upvalue Func has.

	Input:
		1. Function to get upvalues for.
	Output:
		Table of key, value upvalue pairs.
]]
function Shine.GetUpValues( Func )
	local i = 1
	local Values = {}

	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end

		Values[ N ] = Val

		i = i + 1
	end

	return Values
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
function Shine.SetUpValue( Func, Name, Value, Recursive )
	local OldValue, Index, Function = Shine.GetUpValue( Func, Name, Recursive )

	if not OldValue then return nil end
	
	DebugSetUpValue( Function or Func, Index, Value )

	return OldValue
end

--[[
	Replaces all upvalues that have a key in the Values table.

	Inputs:
		1. Function to replace upvalues for.
		2. Values to replace with.
		3. Optional recursion.
]]
function Shine.SetUpValues( Func, Values, Recursive, Done )
	local i = 1
	Done = Done or {}
	if Done[ Func ] then return nil end

	Done[ Func ] = true

	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end
		
		if Values[ N ] then
			DebugSetUpValue( Func, i, Values[ N ] )
		end

		if Recursive and not Done[ Val ] and type( Val ) == "function" then
			Shine.SetUpValues( Val, Values, true, Done )
		end

		i = i + 1
	end
end

--[[
	Copies all upvalues from the given function to your target function.
	Then, replaces any upvalues in DifferingValues in your target function.

	Inputs:
		1. Function to mimic.
		2. Function that will mimic the first function.
		3. Any values you want to set different to their original ones.
	Output:
		The final table of upvalues that TargetFunc now has. Use this if you
		want to then mimic further functions.
]]
function Shine.MimicFunction( Func, TargetFunc, DifferingValues, Recursive )
	local UpValues = Shine.GetUpValues( Func )

	if DifferingValues then
		for Name, Value in pairs( DifferingValues ) do
			UpValues[ Name ] = Value
		end
	end

	--Recursive here means we replace upvalues in the original function's function upvalues.
	if Recursive and DifferingValues then
		local Done = {}
		for Name, Value in pairs( UpValues ) do
			if type( Value ) == "function" then
				Shine.SetUpValues( Value, DifferingValues, true, Done )
			end
		end
	end

	--We don't need to pass the recursive flag as we already did it above.
	Shine.SetUpValues( TargetFunc, UpValues )

	return UpValues
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

--[[
	Gets all local values in a table at the given stack level.

	Input:
		1. Stack level. 2 is added to this number.
	Output:
		Table of local values.
]]
function Shine.GetLocals( Stacklevel )
	Stacklevel = Stacklevel and ( Stacklevel + 2 ) or 3

	local i = 1
	local Values = {}

	while true do
		local Name, Value = DebugGetLocal( Stacklevel, i )

		if not Name then break end

		if Name ~= "(*temporary)" then
			Values[ Name ] = Value
		end

		i = i + 1
	end

	return Values
end
