--[[
	Shine table library.
]]

local IsType = Shine.IsType
local pairs = pairs
local Random = math.random
local TableSort = table.sort

--[[
	Returns true if the given array structures have the same size
	and equal elements in order.
]]
function table.ArraysEqual( Left, Right )
	if #Left ~= #Right then return false end

	for i = 1, #Left do
		if Left[ i ] ~= Right[ i ] then
			return false
		end
	end

	return true
end

do
	local function HasValue( Table, Value )
		for i = 1, #Table do
			if Table[ i ] == Value then
				return true, i
			end
		end

		return false
	end
	table.HasValue = HasValue

	function table.InsertUnique( Table, Value )
		if HasValue( Table, Value ) then return false end

		Table[ #Table + 1 ] = Value

		return true
	end
end

do
	local select = select

	--[[
		Takes a base table and a list of keys, and populates down to the last key with tables.
	]]
	function table.Build( Base, ... )
		for i = 1, select( "#", ... ) do
			local Key = select( i, ... )
			local Entry = Base[ Key ]
			if not Entry then
				Entry = {}
				Base[ Key ] = Entry
			end
			Base = Entry
		end

		return Base
	end
end

--[[
	Finds a table entry by the value of the given field.
]]
function table.FindByField( Table, Field, Value )
	for i = 1, #Table do
		if Table[ i ][ Field ] == Value then
			return Table[ i ], i
		end
	end

	return nil
end

--[[
	Returns a table that contains the given table's values as keys.
]]
function table.AsSet( Table )
	local Ret = {}

	for i = 1, #Table do
		Ret[ Table[ i ] ] = true
	end

	return Ret
end

do
	local TableRemove = table.remove

	--[[
		Finds and removes the given value from the given table.
	]]
	function table.RemoveByValue( Table, Value )
		for i = 1, #Table do
			if Table[ i ] == Value then
				TableRemove( Table, i )
				return true
			end
		end

		return false
	end
end

--[[
	Copies all values under the given keys from the source to the destination table.
]]
function table.Mixin( Source, Destination, Keys )
	for i = 1, #Keys do
		Destination[ Keys[ i ] ] = Source[ Keys[ i ] ]
	end
end

do
	local rawget = rawget
	local function Get( Table, Key )
		return Table[ Key ]
	end

	--[[
		Merges any missing keys in the destination table from the source table.
		Does not recurse.
	]]
	function table.ShallowMerge( Source, Destination, Raw )
		local Getter = Raw and rawget or Get

		for Key, Value in pairs( Source ) do
			if Getter( Destination, Key ) == nil then
				Destination[ Key ] = Value
			end
		end

		return Destination
	end
end

--[[
	Returns a new table that holds the same elements as the input table but in reverse order.
]]
function table.Reverse( Table )
	local Ret = {}
	local Length = #Table

	for i = 1, Length do
		Ret[ Length - i + 1 ] = Table[ i ]
	end

	return Ret
end

--[[
	Clears a table.
]]
function table.Empty( Table )
	for Key in pairs( Table ) do
		Table[ Key ] = nil
	end
end

--[[
	Fixes an array with holes in it.
]]
function table.FixArray( Table )
	local Array = {}
	local Largest = 0

	--Get the upper bound key, cannot rely on #Table or table.Count.
	for Key in pairs( Table ) do
		if Key > Largest then
			Largest = Key
		end
	end

	--Nothing to do, it's an empty table.
	if Largest == 0 then return end

	local Count = 0

	--Clear out the table, and store values in order into the array.
	for i = 1, Largest do
		local Value = Table[ i ]

		if Value ~= nil then
			Count = Count + 1

			Array[ Count ] = Value
			Table[ i ] = nil
		end
	end

	--Restore the values to the original table in array form.
	for i = 1, Count do
		Table[ i ] = Array[ i ]
	end
end

do
	--[[
		Shuffles a table randomly assuming there are no gaps.
	]]
	local function QuickShuffle( Table )
		for i = #Table, 2, -1 do
			local j = Random( i )
			Table[ i ], Table[ j ] = Table[ j ], Table[ i ]
		end
	end
	table.QuickShuffle = QuickShuffle

	--[[
		Shuffles a table randomly, accounting for gaps in the array structure.
	]]
	function table.Shuffle( Table )
		local NewTable = {}
		local Count = 0

		for Index, Value in pairs( Table ) do
			--Add the value to a new table to get rid of potential holes in the array.
			Count = Count + 1
			NewTable[ Count ] = Value
			Table[ Index ] = nil
		end

		QuickShuffle( NewTable )

		--Repopulate the input table with our sorted table. This won't have holes.
		for i = 1, Count do
			Table[ i ] = NewTable[ i ]
		end
	end
end

--[[
	Chooses a random entry from the table
	with each entry having equal probability of being picked.
]]
function table.ChooseRandom( Table )
	local Index = Random( 1, #Table )
	return Table[ Index ], Index
end

--[[
	Returns the average of the numerical values in the table.
]]
function table.Average( Table )
	local Count = #Table
	if Count == 0 then return 0 end

	local Sum = 0

	for i = 1, Count do
		Sum = Sum + Table[ i ]
	end

	return Sum / Count
end

do
	local Notify = Shared.Message
	local StringFormat = string.format
	local StringLower = string.lower
	local StringRep = string.rep
	local TableConcat = table.concat
	local tonumber = tonumber
	local tostring = tostring
	local type = type

	local function ToPrintKey( Key )
		local Type = type( Key )

		if Type ~= "string" then
			return StringFormat( "[ %s ]", tostring( Key ) )
		end

		if Type == "string" and tonumber( Key ) then
			return StringFormat( "[ \"%s\" ]", Key )
		end

		return tostring( Key )
	end
	local function ToPrintString( Value )
		if IsType( Value, "string" ) then
			return StringFormat( "\"%s\"", Value )
		end

		return tostring( Value )
	end

	local function KeySorter( A, B )
		local AIsNumber = IsType( A, "number" )
		local BIsNumber = IsType( B, "number" )
		if AIsNumber and BIsNumber then
			return A < B
		end

		if AIsNumber then
			return true
		end

		if BIsNumber then
			return false
		end

		return StringLower( tostring( A ) ) < StringLower( tostring( B ) )
	end

	local function TableToString( Table, Indent, Done )
		if not IsType( Table, "table" ) then
			error( StringFormat( "bad argument #1 to 'table.ToString' (expected table, got %s)",
				type( Table ) ), 2 )
		end

		Indent = Indent or 1
		Done = Done or {}

		local Strings = {}
		Strings[ 1 ] = StringFormat( "%s {", tostring( Table ) )
		if not next( Table ) then
			return Strings[ 1 ].."}"
		end

		local IndentString = StringRep( "\t", Indent )

		local Keys = {}
		for Key in pairs( Table ) do
			Keys[ #Keys + 1 ] = Key
		end

		TableSort( Keys, KeySorter )

		for i = 1, #Keys do
			local Key = Keys[ i ]
			local Value = Table[ Key ]

			if IsType( Value, "table" ) and not Done[ Value ] then
				Done[ Value ] = true
				local TableAsString = TableToString( Value, Indent + 1, Done )
				Strings[ #Strings + 1 ] = StringFormat( "%s%s = %s", IndentString,
					ToPrintKey( Key ), TableAsString )
			else
				Strings[ #Strings + 1 ] = StringFormat( "%s%s = %s", IndentString,
					ToPrintKey( Key ), ToPrintString( Value ) )
			end
		end

		Strings[ #Strings + 1 ] = StringFormat( "%s}", StringRep( "\t", Indent - 1 ) )

		return TableConcat( Strings, "\n" )
	end
	table.ToString = TableToString

	--[[
		Prints a nicely formatted table structure to the console.
	]]
	function PrintTable( Table )
		Notify( TableToString( Table ) )
	end

	function table.ToDebugString( Table )
		local Strings = {}

		for Key, Value in pairs( Table ) do
			Strings[ #Strings + 1 ] = StringFormat( "%s = %s", ToPrintKey( Key ),
				ToPrintString( Value ) )
		end

		return TableConcat( Strings, "\n" )
	end
end

do
	local getmetatable = getmetatable
	local setmetatable = setmetatable

	local function CopyTable( Table, LookupTable )
		if not Table then return nil end

		local Copy = {}
		setmetatable( Copy, getmetatable( Table ) )

		for Key, Value in pairs( Table ) do
			if not IsType( Value, "table" ) then
				Copy[ Key ] = Value
			else
				LookupTable = LookupTable or {}
				LookupTable[ Table ] = Copy

				if LookupTable[ Value ] then
					Copy[ Key ] = LookupTable[ Value ]
				else
					Copy[ Key ] = CopyTable( Value, LookupTable )
				end
			end
		end

		return Copy
	end
	table.Copy = CopyTable
end

--[[
	Copies an array-like structure without recursion.
]]
function table.QuickCopy( Table )
	local Copy = {}

	for i = 1, #Table do
		Copy[ i ] = Table[ i ]
	end

	return Copy
end

do
	--[[
		Returns an array of all keys in the given table in an undefined order.
	]]
	local function GetKeys( Table )
		local Keys = {}
		local Count = 0

		for Key in pairs( Table ) do
			Count = Count + 1
			Keys[ Count ] = Key
		end

		return Keys, Count
	end
	table.GetKeys = GetKeys

	--[[
		Returns the number of keys in the table.
	]]
	function table.Count( Table )
		local Keys, Count = GetKeys( Table )
		return Count
	end

	local function KeyValueIterator( Keys, Table )
		local i = 1
		return function()
			local Key = Keys[ i ]
			if Key == nil then return nil end

			local Value = Table[ Key ]

			i = i + 1

			return Key, Value
		end
	end

	local QuickShuffle = table.QuickShuffle

	--[[
		Iterates the given table's key-value pairs in a random order.
	]]
	function RandomPairs( Table )
		local Keys = GetKeys( Table )
		QuickShuffle( Keys )

		return KeyValueIterator( Keys, Table )
	end

	--[[
		Iterates the given table's key-value pairs in the order the table's
		keys are naturally sorted.
	]]
	function SortedPairs( Table, Desc )
		local Keys = GetKeys( Table )
		if Desc then
			TableSort( Keys, function( A, B )
				return A > B
			end )
		else
			TableSort( Keys )
		end

		return KeyValueIterator( Keys, Table )
	end
end
