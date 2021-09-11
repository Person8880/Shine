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

	--[[
		Gets the value under the given field on the given table.

		If the field is a table, it is interpreted as a path to the desired value, e.g.
			table.GetField( Table, { "A", "B", "C" } ) => Table.A.B.C
		If the value at an intermediate field is not a table, nil is returned.
	]]
	function table.GetField( Table, FieldName )
		if IsType( FieldName, "table" ) then
			local Root = Table

			for i = 1, #FieldName - 1 do
				Root = Root[ FieldName[ i ] ]
				if not IsType( Root, "table" ) then
					return nil
				end
			end

			return Root[ FieldName[ #FieldName ] ]
		end

		return Table[ FieldName ]
	end

	--[[
		Sets the value under the given field to the given value on the given table.

		Like GetField, this will follow a given path if the field is a table.
			table.SetField( Table, { "A", "B", "C" }, true ) => Table.A.B.C = true
		Any field along the path that is not a table will be replaced with an empty table.
	]]
	function table.SetField( Table, FieldName, Value )
		if IsType( FieldName, "table" ) then
			local Root = Table

			for i = 1, #FieldName - 1 do
				local Child = Root[ FieldName[ i ] ]
				if not IsType( Child, "table" ) then
					Child = {}
					Root[ FieldName[ i ] ] = Child
				end
				Root = Child
			end

			Root[ FieldName[ #FieldName ] ] = Value

			return
		end

		Table[ FieldName ] = Value
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
	local function DefaultTransformer( Index, Value )
		return Value
	end

	--[[
		Returns a table that contains the given table's values as keys,
		as well as the original table values.
	]]
	function table.AsEnum( Table, KeyTransformer )
		KeyTransformer = KeyTransformer or DefaultTransformer

		local Ret = {}

		for i = 1, #Table do
			Ret[ i ] = Table[ i ]
			Ret[ Table[ i ] ] = KeyTransformer( i, Table[ i ] )
		end

		return Ret
	end
end

--[[
	Adds all elements in the source table to the destination table.
]]
function table.Add( Destination, Source )
	for i = 1, #Source do
		Destination[ #Destination + 1 ] = Source[ i ]
	end
	return Destination
end

--[[
	Returns a range of values from the given table.
]]
function table.Slice( Table, StartIndex, EndIndex )
	EndIndex = EndIndex or #Table

	local Ret = {}
	for i = StartIndex, EndIndex do
		Ret[ #Ret + 1 ] = Table[ i ]
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
	Removes the value at the given index without preserving order in constant time.
]]
function table.QuickRemove( Table, Index, Length )
	Table[ Index ] = Table[ Length ]
	Table[ Length ] = nil
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
table.Empty = require "table.clear"

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

do
	local Notify = Shared.Message
	local StringFormat = string.format
	local StringLower = string.lower
	local StringRep = string.rep
	local TableConcat = table.concat
	local type = type

	local Inspect = require "shine/lib/inspect"
	local SafeToString = Inspect.SafeToString
	local ToString = Inspect.ToString
	local ToShortString = Inspect.ToShortString
	local ToShortStringKey = Inspect.ToShortStringKey

	local function ToPrintKey( Key )
		return StringFormat( "[ %s ]", ToString( Key ) )
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

		return StringLower( SafeToString( A ) ) < StringLower( SafeToString( B ) )
	end

	local function TableToString( Table, Indent, Done )
		if not IsType( Table, "table" ) then
			error( StringFormat( "bad argument #1 to 'table.ToString' (expected table, got %s)",
				type( Table ) ), 2 )
		end

		Indent = Indent or 1
		Done = Done or {}

		local Strings = {}
		Strings[ 1 ] = StringFormat( "%s {", SafeToString( Table ) )
		if not next( Table ) then
			return Strings[ 1 ].."}"
		end

		local IndentString = StringRep( "\t", Indent )

		local Keys = GetKeys( Table )
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
					ToPrintKey( Key ), ToString( Value ) )
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

	function table.ToDebugString( Table, Indent )
		Indent = Indent or ""

		local Strings = {}
		local Keys = GetKeys( Table )
		TableSort( Keys, KeySorter )

		for i = 1, #Keys do
			local Key = Keys[ i ]
			local Value = Table[ Key ]
			Strings[ #Strings + 1 ] = StringFormat(
				"%s%s = %s",
				Indent,
				ToShortStringKey( Key ),
				ToShortString( Value )
			)
		end

		return TableConcat( Strings, "\n" )
	end
end

do
	local getmetatable = getmetatable
	local setmetatable = setmetatable

	local function CopyTable( Table, LookupTable )
		if not Table then return nil end

		LookupTable = LookupTable or {}

		local Copy = {}
		LookupTable[ Table ] = Copy
		setmetatable( Copy, getmetatable( Table ) )

		for Key, Value in pairs( Table ) do
			if not IsType( Value, "table" ) then
				Copy[ Key ] = Value
			else
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

--[[
	Copies an arbitrary table structure without deep-copying values.
]]
function table.ShallowCopy( Table )
	local Copy = {}

	for Key, Value in pairs( Table ) do
		Copy[ Key ] = Value
	end

	return Copy
end

do
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

	local DebugGetMetatable = debug.getmetatable
	local tostring = tostring
	local type = type

	local ComparableTypes = {
		number = true,
		string = true
	}

	local function IsComparable( A, B )
		local LeftType = type( A )
		local RightType = type( B )

		-- Identical types on either side, and comparable (e.g. number vs number).
		if LeftType == RightType and ComparableTypes[ LeftType ] then return true end

		local LeftMeta = DebugGetMetatable( A )
		local RightMeta = DebugGetMetatable( B )

		-- Two Lua objects are comparable if the appropriate meta-methods are the same on
		-- the objects on either side. In this case we only need __lt.
		if LeftMeta and LeftMeta.__lt and RightMeta and RightMeta.__lt == LeftMeta.__lt then
			return true
		end

		-- Different or non-existent __lt, so not comparable.
		return false
	end

	local function NaturalOrder( A, B )
		if IsComparable( A, B ) then
			return A < B
		end

		return tostring( A ) < tostring( B )
	end
	local function ReverseNaturalOrder( A, B )
		if IsComparable( A, B ) then
			return A > B
		end

		return tostring( A ) > tostring( B )
	end

	--[[
		Iterates the given table's key-value pairs in the order the table's
		keys are naturally sorted.
	]]
	function SortedPairs( Table, Desc )
		local Keys = GetKeys( Table )
		if Desc then
			TableSort( Keys, ReverseNaturalOrder )
		else
			TableSort( Keys, NaturalOrder )
		end

		return KeyValueIterator( Keys, Table )
	end
end

do
	local assert = assert
	local Floor = math.floor
	local GetMetaTable = debug.getmetatable
	local Max = math.max
	local pairs = pairs
	local setmetatable = setmetatable
	local StringFormat = string.format
	local StringRep = string.rep
	local StringSub = string.sub
	local StringUTF8Chars = string.UTF8Chars
	local TableConcat = table.concat
	local TableEmpty = table.Empty
	local TableNew = require "table.new"
	local tostring = tostring
	local type = type

	local OBJECT_TYPE = "object"
	local function IsTableArray( Table, MetaTable )
		if MetaTable and MetaTable.__jsontype == OBJECT_TYPE then
			return false
		end

		local NumberOfElements = 0
		local ProvidedSize = Table.n or #Table
		local MaxIndex = 0

		for Key, Value in pairs( Table ) do
			if type( Key ) ~= "number" or Key < 1 or Floor( Key ) ~= Key then
				return false
			end

			MaxIndex = Max( Key, MaxIndex )
			NumberOfElements = NumberOfElements + 1
		end

		if MaxIndex > 10 and MaxIndex > ProvidedSize and MaxIndex > NumberOfElements * 2 then
			-- Keep consistent behaviour with DKJSON (avoiding arrays with large gaps between keys)
			return false
		end

		return true, MaxIndex
	end

	local function AddNewLine( Buffer, BufferCount, NewLineChar, IndentText )
		Buffer[ BufferCount + 1 ] = NewLineChar
		Buffer[ BufferCount + 2 ] = IndentText
		return BufferCount + 2
	end

	local ToJSON
	local ESCAPE_CHARS = setmetatable( {
		[ "\"" ] = "\\\"", [ "\\" ] = "\\\\", [ "\b" ] = "\\b",
		[ "\f" ] = "\\f", [ "\n" ] = "\\n",  [ "\r" ] = "\\r",
		[ "\t" ] = "\\t"
	}, {
		__index = function( self, Char ) return Char end
	} )

	local function ToUnicodeEscape( Value )
		return StringFormat( "\\u%.4x", Value )
	end

	-- The JSON specification states that normal unicode characters do not need to be escaped.
	-- Thus we just escape the control characters it states are needed, plus a few extra
	-- such as the null byte.
	local function AddEscapeChar( ByteValue, Encoder )
		local Char = string.char( ByteValue )
		if not rawget( ESCAPE_CHARS, Char ) then
			ESCAPE_CHARS[ Char ] = Encoder( ByteValue )
		end
	end

	for i = 0, 31 do
		AddEscapeChar( i, ToUnicodeEscape )
	end
	for i = 32, 126 do
		AddEscapeChar( i, string.char )
	end
	for i = 127, 159 do
		AddEscapeChar( i, ToUnicodeEscape )
	end
	for i = 160, 255 do
		AddEscapeChar( i, string.char )
	end

	local StringBuff = TableNew( 100, 0 )
	local function EscapeSpecialChars( String )
		TableEmpty( StringBuff )

		local Count = 1

		StringBuff[ 1 ] = "\""
		for ByteIndex, Char in StringUTF8Chars( String ) do
			Count = Count + 1
			StringBuff[ Count ] = ESCAPE_CHARS[ Char ]
		end
		Count = Count + 1
		StringBuff[ Count ] = "\""

		return TableConcat( StringBuff )
	end

	local Writers = {
		[ "nil" ] = function() return "null" end,
		[ "boolean" ] = tostring,
		[ "number" ] = tostring,
		[ "table" ] = function( Value, FormattingOptions, State )
			return ToJSON( Value, FormattingOptions, State )
		end,
		[ "string" ] = function( Value, FormattingOptions, State )
			return State.EscapedStrings[ Value ]
		end
	}
	local LengthGetters = {
		[ "nil" ] = function() return 4 end,
		[ "boolean" ] = function( Value ) return #tostring( Value ) end,
		[ "number" ] = function( Value ) return #tostring( Value ) end,
		[ "string" ] = function( Value ) return #Value + 2 end
	}

	local function WriteValue( Value, Buffer, FormattingOptions, State )
		local ValueType = type( Value )

		local Writer = Writers[ ValueType ]
		if not Writer then
			error( StringFormat( "Unsupported value type: %s", ValueType ) )
		end

		local Output = Writer( Value, FormattingOptions, State )
		if Output then
			State.BufferCount = State.BufferCount + 1
			Buffer[ State.BufferCount ] = Output
		end

		return State.BufferCount
	end

	local function DetermineIfArrayFitsOnLine( Table, MaxIndex, FormattingOptions, State )
		-- This doesn't account for the length of the key behind the array, but it's a good
		-- enough approximation.
		local Length = FormattingOptions.IndentSize * State.IndentLevel
		local SEPARATOR_LENGTH = 2
		local PrintMargin = FormattingOptions.PrintMargin

		-- Avoid a costly loop if it looks like the array is too long upfront.
		if Length + MaxIndex * 2 + ( MaxIndex - 1 ) * SEPARATOR_LENGTH > PrintMargin then
			return false
		end

		for i = 1, MaxIndex do
			local Value = Table[ i ]
			local ValueType = type( Value )

			local LengthGetter = LengthGetters[ ValueType ]
			if not LengthGetter then
				-- Objects in the array always look better with newlines.
				return false
			end

			Length = Length + LengthGetter( Value ) + SEPARATOR_LENGTH

			if Length > PrintMargin then
				return false
			end
		end

		return true
	end

	ToJSON = function( Table, FormattingOptions, State )
		assert( not State.Seen[ Table ], "Cycle in input table" )

		State.Seen[ Table ] = true

		local Buffer = State.Buffer
		local BufferCount = State.BufferCount
		local IsArray, MaxIndex = IsTableArray( Table, GetMetaTable( Table ) )
		local IsPrettyPrint = FormattingOptions.PrettyPrint
		local NewLineChar = FormattingOptions.NewLineChar

		if IsArray then
			BufferCount = BufferCount + 1
			Buffer[ BufferCount ] = "["

			State.IndentLevel = State.IndentLevel + 1

			local ShouldSeparate = false
			if IsPrettyPrint then
				ShouldSeparate = not DetermineIfArrayFitsOnLine( Table, MaxIndex, FormattingOptions, State )
			end

			for i = 1, MaxIndex do
				if IsPrettyPrint then
					if ShouldSeparate then
						BufferCount = AddNewLine(
							Buffer, BufferCount, NewLineChar, State.Indents[ State.IndentLevel ]
						)
					else
						BufferCount = BufferCount + 1
						Buffer[ BufferCount ] = " "
					end
				end

				State.BufferCount = BufferCount
				BufferCount = WriteValue( Table[ i ], Buffer, FormattingOptions, State )

				if i ~= MaxIndex then
					BufferCount = BufferCount + 1
					Buffer[ BufferCount ] = ","
				elseif not ShouldSeparate and IsPrettyPrint then
					BufferCount = BufferCount + 1
					Buffer[ BufferCount ] = " "
				end
			end

			State.IndentLevel = State.IndentLevel - 1

			if MaxIndex >= 1 and ShouldSeparate then
				BufferCount = AddNewLine( Buffer, BufferCount, NewLineChar, State.Indents[ State.IndentLevel ] )
			end

			BufferCount = BufferCount + 1
			Buffer[ BufferCount ] = "]"
		else
			BufferCount = BufferCount + 1
			Buffer[ BufferCount ] = "{"
			State.IndentLevel = State.IndentLevel + 1

			local WroteValues = false
			for Key, Value in FormattingOptions.TableIterator( Table ) do
				if WroteValues then
					BufferCount = BufferCount + 1
					Buffer[ BufferCount ] = ","
				end

				WroteValues = true
				if IsPrettyPrint then
					BufferCount = AddNewLine( Buffer, BufferCount, NewLineChar, State.Indents[ State.IndentLevel ] )
				end

				local KeyType = type( Key )
				if KeyType == "number" then
					State.BufferCount = BufferCount
					BufferCount = WriteValue( Key, Buffer, FormattingOptions, State )

					Buffer[ BufferCount ] = StringFormat( "\"%s\"", Buffer[ BufferCount ] )
				elseif KeyType == "string" then
					State.BufferCount = BufferCount
					BufferCount = WriteValue( Key, Buffer, FormattingOptions, State )
				else
					error( "Unsupported table key type: "..KeyType )
				end

				BufferCount = BufferCount + 1
				Buffer[ BufferCount ] = ":"

				if IsPrettyPrint then
					BufferCount = BufferCount + 1
					Buffer[ BufferCount ] = " "
				end

				State.BufferCount = BufferCount
				BufferCount = WriteValue( Value, Buffer, FormattingOptions, State )
			end

			State.IndentLevel = State.IndentLevel - 1
			if WroteValues and IsPrettyPrint then
				BufferCount = AddNewLine( Buffer, BufferCount, NewLineChar, State.Indents[ State.IndentLevel ] )
			end

			BufferCount = BufferCount + 1
			Buffer[ BufferCount ] = "}"
		end

		State.BufferCount = BufferCount
		State.Seen[ Table ] = false
	end

	local DEFAULT_OPTIONS = {
		-- Whether to print the output in a nice, human-readable format.
		PrettyPrint = true,
		-- The number of times to repeat the indent character per indent level.
		IndentSize = 4,
		-- The indent character (ideally " " or "\t").
		IndentChar = " ",
		-- The new line character.
		NewLineChar = "\n",
		-- The iterator to use to iterate non-array tables.
		TableIterator = SortedPairs,
		-- Roughly how far along to allow text before wrapping arrays in pretty print mode.
		PrintMargin = 80
	}
	local InheritFromDefault = { __index = DEFAULT_OPTIONS }

	-- Cache indent strings to avoid costly repeated string.rep calls.
	local StateIndentCache = {
		__index = function( self, IndentLevel )
			local Indent = StringRep( self.IndentChar, self.IndentSize * IndentLevel )
			self[ IndentLevel ] = Indent
			return Indent
		end
	}

	-- Cache escaped string values to improve performance when the same string is repeated many times.
	local StateEscapeCache = {
		__index = function( self, String )
			local EscapedString = EscapeSpecialChars( String )
			self[ String ] = EscapedString
			return EscapedString
		end
	}

	--[[
		Outputs a table in JSON form, providing better formatting options than
		DKJSON.

		Unlike DKJSON, this throws any error encountered while serialising.
	]]
	function table.ToJSON( Table, FormattingOptions )
		if not FormattingOptions then
			FormattingOptions = DEFAULT_OPTIONS
		else
			FormattingOptions = setmetatable( FormattingOptions, InheritFromDefault )
		end

		local Indents = setmetatable( TableNew( 5, 0 ), StateIndentCache )
		Indents.IndentSize = FormattingOptions.IndentSize
		Indents.IndentChar = FormattingOptions.IndentChar

		local State = {
			BufferCount = 0,
			IndentLevel = 0,
			Seen = TableNew( 0, 20 ),
			Buffer = TableNew( 100, 0 ),
			Indents = Indents,
			EscapedStrings = setmetatable( TableNew( 0, 20 ), StateEscapeCache )
		}

		ToJSON( Table, FormattingOptions, State )

		TableEmpty( StringBuff )

		return TableConcat( State.Buffer )
	end
end
