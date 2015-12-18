--[[
	Shine table library.
]]

local IsType = Shine.IsType
local pairs = pairs
local Random = math.random
local TableRemove = table.remove
local TableSort = table.sort

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

--[[
	Copies all values under the given keys from the source to the destination table.
]]
function table.Mixin( Source, Destination, Keys )
	for i = 1, #Keys do
		Destination[ Keys[ i ] ] = Source[ Keys[ i ] ]
	end
end

--[[
	Merges any missing keys in the destination table from the source table.
	Does not recurse.
]]
function table.ShallowMerge( Source, Destination )
	for Key, Value in pairs( Source ) do
		if Destination[ Key ] == nil then
			Destination[ Key ] = Value
		end
	end

	return Destination
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
local function TableEmpty( Table )
	for Key in pairs( Table ) do
		Table[ Key ] = nil
	end
end
table.Empty = TableEmpty

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

--[[
	Shuffles a table randomly.
]]
function table.Shuffle( Table )
	local SortTable = {}
	local NewTable = {}

	local Count = 0

	for Index, Value in pairs( Table ) do
		SortTable[ Value ] = Random()

		--Add the value to a new table to get rid of potential holes in the array.
		Count = Count + 1
		NewTable[ Count ] = Value

		Table[ Index ] = nil
	end

	TableSort( NewTable, function( A, B )
		return SortTable[ A ] > SortTable[ B ]
	end )

	--Repopulate the input table with our sorted table. This won't have holes.
	for i = 1, Count do
		Table[ i ] = NewTable[ i ]
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
	local StringRep = string.rep
	local TableConcat = table.concat
	local tonumber = tonumber
	local tostring = tostring
	local type = type

	local function ToPrintKey( Key )
		local Type = type( Key )

		if Type ~= "string" and Type ~= "number" then
			return StringFormat( "[ %s ]", tostring( Key ) )
		end

		if Type == "string" and tonumber( Key ) then
			return StringFormat( "\"%s\"", Key )
		end

		return tostring( Key )
	end
	local function ToPrintString( Value )
		if IsType( Value, "string" ) then
			return StringFormat( "\"%s\"", Value )
		end

		return tostring( Value )
	end

	local function TableToString( Table, Indent, Done )
		Indent = Indent or 1
		Done = Done or {}

		local Strings = {}
		Strings[ 1 ] = StringFormat( "%s {", tostring( Table ) )
		if not next( Table ) then
			return Strings[ 1 ].."}"
		end

		local IndentString = StringRep( "\t", Indent )

		for Key, Value in pairs( Table ) do
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

function table.Count( Table )
	local i = 0

	for Key in pairs( Table ) do
		i = i + 1
	end

	return i
end

function RandomPairs( Table, Desc )
	local Sorted = {}
	local Count = 0

	for Key in pairs( Table ) do
		Count = Count + 1
		Sorted[ Count ] = { Key = Key, Rand = Random() }
	end

	if Desc then
		TableSort( Sorted, function( A, B )
			return A.Rand > B.Rand
		end )
	else
		TableSort( Sorted, function( A, B )
			return A.Rand < B.Rand
		end )
	end

	local i = 1

	return function()
		local Key = Sorted[ i ] and Sorted[ i ].Key
		if Key == nil then return nil end

		local Value = Table[ Key ]

		i = i + 1

		return Key, Value
	end
end

function SortedPairs( Table, Desc )
	local Sorted = {}
	local Count = 0

	for Key in pairs( Table ) do
		Count = Count + 1
		Sorted[ Count ] = Key
	end

	if Desc then
		TableSort( Sorted, function( A, B )
			return A > B
		end )
	else
		TableSort( Sorted, function( A, B )
			return A < B
		end )
	end

	local i = 1

	return function()
		local Key = Sorted[ i ]
		if Key == nil then return nil end

		local Value = Table[ Key ]

		i = i + 1

		return Key, Value
	end
end
