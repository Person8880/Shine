--[[
	Shine debug library.
]]

local assert = assert
local DebugGetInfo = debug.getinfo
local DebugGetLocal = debug.getlocal
local DebugGetMetaField = debug.getmetafield
local DebugGetUpValue = debug.getupvalue
local DebugIsCFunction = debug.iscfunction
local DebugSetUpValue = debug.setupvalue
local DebugUpValueJoin = debug.upvaluejoin
local pairs = pairs
local StringFormat = string.format
local StringStartsWith = string.StartsWith
local type = type

if not DebugGetMetaField then
	local DebugGetMetaTable = debug.getmetatable
	DebugGetMetaField = function( Table, Field )
		local MetaTable = DebugGetMetaTable( Table )
		return MetaTable and MetaTable[ Field ]
	end
	debug.getmetafield = DebugGetMetaField
end

if not DebugIsCFunction then
	DebugIsCFunction = function( Func )
		assert( type( Func ) == "function", "bad argument #1 to 'iscfunction' (expected function)" )
		local Info = DebugGetInfo( Func )
		return not not ( Info and Info.what == "C" )
	end
	debug.iscfunction = DebugIsCFunction
end

local function ForEachUpValue( Func, Filter, Recursive, Done )
	-- Don't attempt to inspect C-functions, their upvalues are forbidden (and of no legitimate use anyway).
	if DebugIsCFunction( Func ) then return nil end

	--Avoid upvalue cycles (it is possible.)
	Done = Done or {}
	if Done[ Func ] then return nil end

	Done[ Func ] = true

	local i = 1
	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end

		if Filter( Func, N, Val, i ) then
			return Val, i, Func
		end

		if Recursive and not Done[ Val ] and type( Val ) == "function" then
			local LowerVal, j, Function = ForEachUpValue( Val, Filter, true, Done )
			if LowerVal ~= nil then
				return LowerVal, j, Function
			end
		end

		i = i + 1
	end
end

--[[
	Gets an upvalue from the given function.

	Inputs:
		1. Function to get the upvalue from.
		2. Name of the upvalue variable.
		3. Boolean flag to indicate whether function upvalues should also be searched.
	Outputs:
		1. Upvalue or nil if not found.
		2. Index at which the upvalue was found.
		3. Function the upvalue was found first in.
]]
function Shine.GetUpValue( Func, Name, Recursive )
	return ForEachUpValue( Func, function( Function, N, Val, i )
		return N == Name
	end, Recursive )
end

--[[
	Finds an upvalue in the given function matching the given value.

	Inputs:
		1. Function to search.
		2. Value to match with.
		3. Boolean flag to indicate whether function upvalues should also be searched.
	Outputs:
		1. Upvalue or nil if not found.
		2. Index at which the upvalue was found.
		3. Function the upvalue was found first in.
]]
function Shine.FindUpValue( Func, Value, Recursive, Done )
	return ForEachUpValue( Func, function( Function, N, Val, i )
		return Val == Value
	end, Recursive )
end

--[[
	Returns a table containing every upvalue Func has.

	Input:
		1. Function to get upvalues for.
	Output:
		Table of key, value upvalue pairs.
]]
function Shine.GetUpValues( Func )
	local Values = {}

	ForEachUpValue( Func, function( Function, N, Val, i )
		Values[ N ] = Val
	end )

	return Values
end

--[[
	Sets an upvalue for the given function.

	Inputs:
		1. Function to set the upvalue for.
		2. Name of the upvalue variable.
		3. New value to set as the upvalue's value.
		4. Boolean flag to indicate whether function upvalues should also be searched.
	Output:
		Old value on success, or nil on failure.
]]
function Shine.SetUpValue( Func, Name, Value, Recursive )
	local OldValue, Index, Function = Shine.GetUpValue( Func, Name, Recursive )

	if not Index then return nil end

	DebugSetUpValue( Function, Index, Value )

	return OldValue
end

--[[
	Sets an upvalue for the given function by matching against the given value.

	Inputs:
		1. Function to set the upvalue for.
		2. Value to search for.
		3. New value to set as the upvalue's value.
		4. Boolean flag to indicate whether function upvalues should also be searched.
	Output:
		Old value on success, or nil on failure.
]]
function Shine.SetUpValueByValue( Func, Value, NewValue, Recursive )
	local OldValue, Index, Function = Shine.FindUpValue( Func, Value, Recursive )

	if not Index then return nil end

	DebugSetUpValue( Function, Index, NewValue )

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
	ForEachUpValue( Func, function( Function, N, Val, i )
		if Values[ N ] then
			DebugSetUpValue( Function, i, Values[ N ] )
		end
	end, Recursive )
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
	Joins the upvalues of TargetFunc to those of Func, following the mapping given.

	Inputs:
		1. The function whose upvalues should be joined from.
		2. The function whose upvalues should be joined to.
		3. A table defining a map of upvalue name from function 1,
		   mapping to the name of the upvalue in function 2.

	For example:

	Shine.JoinUpValues( Func, TargetFunc, {
		UpValue1 = "OtherUpValue",
		UpValue2 = "OtherUpValue2"
	} )

	maps UpValue1 in Func to OtherUpValue in TargetFunc, and UpValue2 in Func to OtherUpValue2 in TargetFunc.

	This avoids needing to constantly get up values.
]]
function Shine.JoinUpValues( Func, TargetFunc, Mapping, Recursive )
	local UpValueIndex = {}
	local InverseMapping = {}

	ForEachUpValue( Func, function( Function, Name, Value, i )
		local MappedName = Mapping[ Name ]
		if not MappedName then return end

		if type( MappedName ) == "table" then
			if Shine.IsCallable( MappedName.Predicate ) and not MappedName.Predicate( Function, Name, Value ) then
				return
			end

			MappedName = MappedName.Name
		end

		UpValueIndex[ Name ] = {
			Function = Function,
			Index = i
		}
		InverseMapping[ MappedName ] = Name
	end, Recursive )

	ForEachUpValue( TargetFunc, function( Function, Name, Value, i )
		if InverseMapping[ Name ] then
			local UpValue = UpValueIndex[ InverseMapping[ Name ] ]
			DebugUpValueJoin( TargetFunc, i, UpValue.Function, UpValue.Index )
		end
	end )
end

Shine.UpValuePredicates = {
	DefinedInFile = function( FileName )
		local SourcePrefix = "@"..FileName
		return function( Func, Name, Value )
			local Info = DebugGetInfo( Func, "S" )
			return StringStartsWith( Info.source, SourcePrefix )
		end
	end
}

--[[
	Returns a function that, when called, returns the current value stored in the
	named upvalue of the given function.
]]
function Shine.GetUpValueAccessor( Function, UpValue, Options )
	local Value
	local function GetValue()
		return Value
	end
	local function SetValue( NewValue )
		Value = NewValue
	end

	local UpValueParams = {
		[ UpValue ] = {
			Name = "Value",
			Predicate = Options and Options.Predicate
		}
	}
	local IsRecursive = Options and Options.Recursive
	Shine.JoinUpValues( Function, GetValue, UpValueParams, IsRecursive )
	Shine.JoinUpValues( Function, SetValue, UpValueParams, IsRecursive )

	return GetValue, SetValue
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
	Determines if a given object is callable. That is, if it is a function
	or its metatable has a __call meta-method.
]]
function Shine.IsCallable( Object )
	if type( Object ) == "function" then return true end

	local MetaCallField = DebugGetMetaField( Object, "__call" )
	return type( MetaCallField ) == "function"
end

--[[
	Asserts a condition at a given level, and formats the error message.

	Inputs:
		1. Assertion condition.
		2. Error message.
		3. Error level.
		4. Format arguments for the error message.
]]
function Shine.AssertAtLevel( Assertion, Error, Level, ... )
	if not Assertion then
		error( StringFormat( Error, ... ), Level )
	end

	return Assertion
end

--[[
	Asserts a condition and formats the error message.

	Inputs:
		1. Assertion condition.
		2. Error message.
		3. Format arguments for the error message.
]]
function Shine.Assert( Assertion, Error, ... )
	return Shine.AssertAtLevel( Assertion, Error, 2, ... )
end

do
	local TableConcat = table.concat
	local function MatchesType( Value, Type )
		local ArgType = type( Value )
		local MatchesType = false
		local ExpectedType = Type

		if type( Type ) == "table" then
			for i = 1, #Type do
				if ArgType == Type[ i ] then
					MatchesType = true
					break
				end
			end

			ExpectedType = TableConcat( Type, " or " )
		else
			MatchesType = ArgType == Type
		end

		return MatchesType, ExpectedType, ArgType
	end

	--[[
		Checks a value's type, and throws an error if it doesn't match.
	]]
	function Shine.TypeCheck( Arg, Type, ArgNumber, FuncName, Level )
		local MatchesType, ExpectedType, ArgType = MatchesType( Arg, Type )
		if not MatchesType then
			error( StringFormat( "Bad argument #%i to '%s' (%s expected, got %s)",
				ArgNumber, FuncName, ExpectedType, ArgType ), Level or 3 )
		end
		return Arg
	end

	--[[
		Checks a field's type, and throws an error if it doesn't match.
	]]
	function Shine.TypeCheckField( Table, FieldName, Type, ObjectName, Level )
		local Value = Table[ FieldName ]

		local MatchesType, ExpectedType, ArgType = MatchesType( Value, Type )
		if not MatchesType then
			error( StringFormat( "Bad value for field '%s' on %s (%s expected, got %s)",
				FieldName, ObjectName, ExpectedType, ArgType ), Level or 3 )
		end

		return Value
	end
end

--[[
	Gets all local values in a table at the given stack level.

	Input:
		1. Stack level. 2 is added to this number.
	Output:
		Table of local values.
]]
function Shine.GetLocals( StackLevel, NilValueMarker )
	StackLevel = StackLevel and ( StackLevel + 1 ) or 2

	local i = 1
	local Values = {}
	local function ToValue( Value )
		if Value == nil then
			return NilValueMarker
		end
		return Value
	end

	while true do
		local Name, Value = DebugGetLocal( StackLevel, i )
		if not Name then break end

		if Name ~= "(*temporary)" then
			Values[ Name ] = ToValue( Value )
		end

		i = i + 1
	end

	local Info = DebugGetInfo( StackLevel )
	if Info and Info.isvararg and Info.what ~= "C" then
		-- Var-args occupy negative indexes, starting at -1 for the first value.
		i = 1
		while true do
			local Name, Value = DebugGetLocal( StackLevel, -i )
			if not Name then
				break
			end

			Values[ StringFormat( "select( %d, ... )", i ) ] = ToValue( Value )

			i = i + 1
		end

		Values[ "select( \"#\", ... )" ] = i - 1
	end

	if Info and Info.func and Info.what ~= "C" then
		-- Extract upvalues if possible.
		i = 1
		while true do
			local Name, Value = DebugGetUpValue( Info.func, i )
			if not Name then
				break
			end

			-- Locals may be named the same as upvalues, in which case the upvalue is irrelevant here.
			if Values[ Name ] == nil then
				Values[ Name ] = ToValue( Value )
			end

			i = i + 1
		end
	end

	return Values
end

do
	local DebugTraceback = debug.traceback
	local StringGSub = string.gsub

	--[[
		Work around Lua 5.1 traceback behaviour where you must provide a string
		to set the traceback level, which adds a useless line.
	]]
	function Shine.Traceback( Level )
		local Trace = DebugTraceback( "", Level + 1 )
		return ( StringGSub( Trace, "^([^\n]*)\n(.*)$", "%2" ) )
	end
end

do
	local TableConcat = table.concat
	local TypeNames = {
		C = function( Info )
			local Name = Info.name and StringFormat( "'%s'", Info.name )
				or StringFormat( "<%s:%d>", Info.short_src, Info.linedefined or -1 )
			return StringFormat( "function %s", Name )
		end,
		main = function() return "main chunk" end
	}
	TypeNames.Lua = TypeNames.C

	local NilMarker = setmetatable( {}, {
		__tostring = function() return "nil" end,
		__PrintAsString = true
	} )

	local INFO_MASK = "Snl"
	function Shine.StackDump( Level )
		Level = Level or 1

		local CurrentLevel = Level + 1
		local Info = DebugGetInfo( CurrentLevel, INFO_MASK )
		local Output = { "Stack traceback:" }

		while Info do
			local TypePrinter = TypeNames[ Info.what ]
			Output[ #Output + 1 ] = StringFormat( "    %s:%d in %s", Info.short_src,
				Info.currentline or -1, TypePrinter and TypePrinter( Info ) or "?" )

			local Locals = table.ToDebugString( Shine.GetLocals( CurrentLevel, NilMarker ), "        " )
			if Locals ~= "" then
				Output[ #Output + 1 ] = Locals
			end

			CurrentLevel = CurrentLevel + 1
			Info = DebugGetInfo( CurrentLevel, INFO_MASK )
		end

		return TableConcat( Output, "\n" )
	end
end

--[[
	Builds an error handler function for use with xpcall. Reports and logs any errors encountered,
	including the local values of the caller.
]]
function Shine.BuildErrorHandler( ErrorType )
	return function( Err )
		local Trace = Shine.StackDump( 2 )

		Shine:DebugPrint( "%s: %s\n%s", true, ErrorType, Err, Trace )
		Shine:AddErrorReport( StringFormat( "%s: %s", ErrorType, Err ), Trace )

		return Err
	end
end

do
	local SharedMessage = Shared.Message
	local select = select
	local tostring = tostring
	local TableConcat = table.concat

	function LuaPrint( ... )
		local Out = { ... }

		for i = 1, select( "#", ... ) do
			Out[ i ] = tostring( Out[ i ] )
		end

		SharedMessage( TableConcat( Out, "\t" ) )
	end
end
