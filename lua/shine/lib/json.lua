--[[
	JSON helpers.
]]

local setmetatable = setmetatable
local StringFind = string.find
local StringFormat = string.format
local StringSub = string.sub
local StringUTF8Char = string.UTF8Char
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableNew = require "table.new"
local tonumber = tonumber

local JSON = {}

local STATE_INIT = 1
local STATE_OBJECT = 2
local STATE_ARRAY = 3
local STATE_STRING = 4
local STATE_LITERAL = 5
local STATE_NUMBER = 6

local StateByChar = {
	[ "{" ] = STATE_OBJECT,
	[ "[" ] = STATE_ARRAY,
	[ "\"" ] = STATE_STRING,
	[ "t" ] = STATE_LITERAL,
	[ "f" ] = STATE_LITERAL,
	[ "n" ] = STATE_LITERAL,
	[ "-" ] = STATE_NUMBER,
}
for i = 0, 9 do
	StateByChar[ tostring( i ) ] = STATE_NUMBER
end

local StateTerminators = {
	[ STATE_OBJECT ] = "}",
	[ STATE_ARRAY ] = "]"
}

local UNESCAPED_CHARS = {
	b = "\b",
	f = "\f",
	n = "\n",
	r = "\r",
	t = "\t",
	[ "\\" ] = "\\",
	[ "\"" ] = "\""
}
for i = 0, 255 do
	local Char = string.char( i )
	if not UNESCAPED_CHARS[ Char ] then
		UNESCAPED_CHARS[ Char ] = Char
	end
end

local function GetLineColumn( JSONString, Pos )
	local Index = 1
	local LastLineIndex = 0
	local NumLines = 1

	for i = 1, #JSONString do
		local Line = StringFind( JSONString, "\n", Index, true )
		if not Line or Line >= Pos then
			break
		end

		NumLines = NumLines + 1
		LastLineIndex = Line
		Index = Line + 1
	end

	return NumLines, Pos - LastLineIndex
end

local function SkipWhitespace( JSONString, Context )
	local Pos = Context.Pos

	for i = Pos, #JSONString do
		-- As per the JSON spec, these are the only permitted whitespace characters.
		Pos = StringFind( JSONString, "[^ \n\r\t]", Pos )
		if not Pos then break end

		local PossibleComment = StringSub( JSONString, Pos, Pos + 1 )
		if PossibleComment == "//" then
			-- Assuming no-one's using old \r only line-endings here...
			local NextLine = StringFind( JSONString, "\n", Pos, true )
			if not NextLine then break end

			Pos = NextLine + 1
		elseif PossibleComment == "/*" then
			local _, EndComment = StringFind( JSONString, "*/", Pos, true )
			if not EndComment then break end

			Pos = EndComment + 1
		else
			return StringSub( JSONString, Pos, Pos ), Pos
		end
	end

	return nil, #JSONString + 1, "no valid JSON value (reached the end)"
end

local function ParseUTF16Pair( CodePoint, JSONString, Index )
	if StringSub( JSONString, Index + 6, Index + 7 ) == "\\u" then
		local CodePoint2 = tonumber( StringSub( JSONString, Index + 8, Index + 11 ), 16 )
		if CodePoint2 and CodePoint2 >= 0xDC00 and CodePoint2 <= 0xDFFF then
			CodePoint = ( CodePoint - 0xD800 ) * 0x400 + ( CodePoint2 - 0xDC00 ) + 0x10000
			return CodePoint, Index + 6
		end
	end

	-- 0xD800 - 0xDFFF is invalid UTF-8, ignore it if there's no pair.
	return nil, Index
end

local function ParseEscapedUnicode( JSONString, Index )
	local CodePoint = tonumber( StringSub( JSONString, Index + 2, Index + 5 ), 16 )
	if not CodePoint then return nil, Index end

	-- Check for UTF-16 surrogate pair.
	if CodePoint >= 0xD800 and CodePoint <= 0xDBFF then
		CodePoint, Index = ParseUTF16Pair( CodePoint, JSONString, Index )
	end

	if CodePoint then
		return StringUTF8Char( CodePoint ), Index + 6
	end

	return nil, Index
end

local function FindEndOfString( JSONString, Index )
	for i = Index, #JSONString do
		local NextEndOfString = StringFind( JSONString, "\"", Index, true )
		if not NextEndOfString then break end

		-- Check behind the character to see if it's escaped.
		local NumEscapes = 0
		for j = NextEndOfString - 1, Index, -1 do
			local Char = StringSub( JSONString, j, j )
			if Char ~= "\\" then
				break
			end
			NumEscapes = NumEscapes + 1
		end

		if NumEscapes % 2 == 0 then
			-- Even number, either escaping something else, or there was no \ behind.
			return NextEndOfString
		end

		Index = NextEndOfString + 1
	end

	return nil
end

local ParsedString = TableNew( 100, 0 )
local function UnescapeString( String )
	TableEmpty( ParsedString )

	local CharCount = 0
	local Index = 1

	for i = 1, #String do
		local NextEscape = StringFind( String, "\\", Index, true )
		if not NextEscape then break end

		if NextEscape > Index then
			CharCount = CharCount + 1
			ParsedString[ CharCount ] = StringSub( String, Index, NextEscape - 1 )
		end

		local NextChar = StringSub( String, NextEscape + 1, NextEscape + 1 )
		local UnescapedChar
		if NextChar == "u" then
			UnescapedChar, Index = ParseEscapedUnicode( String, NextEscape )
		end

		if not UnescapedChar then
			UnescapedChar = UNESCAPED_CHARS[ NextChar ]
			Index = NextEscape + 2
		end

		CharCount = CharCount + 1
		ParsedString[ CharCount ] = UnescapedChar
	end

	if Index <= #String then
		CharCount = CharCount + 1
		ParsedString[ CharCount ] = StringSub( String, Index )
	end

	return TableConcat( ParsedString )
end

-- JSON documents often repeat the same strings over and over, this saves time repeating the same unescaping logic
-- when most strings need little if any processing.
local UnescapeStringCache = {
	__index = function( self, String )
		local UnescapedString = UnescapeString( String )
		self[ String ] = UnescapedString
		return UnescapedString
	end
}

local function ParseString( JSONString, Context )
	local Index = Context.Pos + 1
	local EndIndex = FindEndOfString( JSONString, Index )
	if not EndIndex then
		return nil, #JSONString + 1, StringFormat(
			"unterminated string at line %d, column %d", GetLineColumn( JSONString, Index )
		)
	end

	Context.Pos = EndIndex + 1

	local StringContents = StringSub( JSONString, Index, EndIndex - 1 )
	return Context.UnescapedStrings[ StringContents ], EndIndex + 1
end

local function PopState( Context )
	local StateCount = Context.StateCount

	Context.State[ StateCount ] = nil
	Context.StateCount = StateCount - 1

	return true
end

local function PopValue( Context )
	local ValueCount = Context.ValueCount

	Context.Value[ ValueCount ] = nil
	Context.Key[ ValueCount ] = nil
	Context.ValueCount = ValueCount - 1

	return PopState( Context )
end

local function PushValue( Context, Value )
	local ValueCount = Context.ValueCount + 1

	Context.Value[ ValueCount ] = Value
	Context.Key[ ValueCount ] = 0
	Context.ValueCount = ValueCount

	return true
end

local function PushRootValue( Context, Value )
	Context.RootValue = Value
	return PushValue( Context, Value )
end

local function PushStateFromChar( JSONString, Char, Pos, Context )
	local State = StateByChar[ Char ]
	if not State then
		return nil, Pos, StringFormat(
			"no valid JSON value at line %d, column %d", GetLineColumn( JSONString, Pos )
		)
	end

	if State == STATE_OBJECT or State == STATE_ARRAY then
		Context.StateCount = Context.StateCount + 1
		Context.State[ Context.StateCount ] = State
	end

	return State, Pos
end

local function PopTableState( JSONString, Context )
	PopValue( Context )

	local State = Context.State[ Context.StateCount ]
	if State == STATE_OBJECT or State == STATE_ARRAY then
		-- Popping to a parent object/array, need to check if there's a comma following or not.
		local Char, Pos, Err = SkipWhitespace( JSONString, Context )
		if not Char then
			return nil, Pos, Err
		end

		Context.Pos = Pos + 1

		if Char == "," then
			-- There is a comma, assume there's more values in the object/array.
			return true
		end

		-- No comma, thus the object/array must be terminated here, otherwise it's invalid JSON.
		local ExpectedTerminator = StateTerminators[ State ]
		if Char ~= ExpectedTerminator then
			return nil, Pos, StringFormat(
				"',' expected to continue %s at line %d, column %d",
				State == STATE_ARRAY and "array" or "object",
				GetLineColumn( JSONString, Pos )
			)
		end

		-- Keep popping up the stack until there's more expected values or we run out of tables.
		return PopTableState( JSONString, Context )
	end

	return true
end

local MetaTables = {
	[ STATE_OBJECT ] = { __jsontype = "object" },
	[ STATE_ARRAY ] = { __jsontype = "array" }
}
--[[
	Returns a table that, when serialised, will be represented as an object in JSON, rather than an array.
]]
function JSON.Object()
	return setmetatable( {}, MetaTables[ STATE_OBJECT ] )
end

local Parsers
Parsers = {
	[ STATE_INIT ] = function( JSONString, Context )
		local Char, Pos, Err = SkipWhitespace( JSONString, Context )
		if not Char then
			return nil, Pos, Err
		end

		local State, Pos, Err = PushStateFromChar( JSONString, Char, Pos, Context )
		if not State then
			return nil, Pos, Err
		end

		if State ~= STATE_OBJECT and State ~= STATE_ARRAY then
			-- Just a simple value, parse and return it as-is, ignoring anything after it in the string.
			Context.Pos = Pos

			local Value, Pos, Err = Parsers[ State ]( JSONString, Context )
			if Err then
				return nil, Pos, Err
			end

			PushRootValue( Context, Value )

			return true
		end

		Context.Pos = Pos + 1

		return PushRootValue( Context, setmetatable( TableNew( 10, 10 ), MetaTables[ State ] ) )
	end,
	[ STATE_OBJECT ] = function( JSONString, Context )
		local Char, Pos, Err = SkipWhitespace( JSONString, Context )
		if not Char then
			return nil, Pos, Err
		end

		if Char == "}" then
			-- End of object, either there were no key-values, or this follows a comma.
			-- Strictly speaking, an error should be thrown if this follows a comma, but we can continue to parse
			-- so accomodate the mistake and continue.
			Context.Pos = Pos + 1
			return PopTableState( JSONString, Context )
		end

		if Char ~= "\"" then
			return nil, Pos, StringFormat(
				"'\"' expected to start key in object, got \"%s\" at line %d, column %d",
				Char,
				GetLineColumn( JSONString, Pos )
			)
		end

		Context.Pos = Pos

		local Key, Pos, Err = ParseString( JSONString, Context )
		if not Key then
			return nil, Pos, Err
		end

		Char, Pos, Err = SkipWhitespace( JSONString, Context )
		if not Char then
			return nil, Pos, Err
		end

		if Char ~= ":" then
			return nil, Pos, StringFormat(
				"':' expected after object key at line %d, column %d", GetLineColumn( JSONString, Pos )
			)
		end

		Context.Pos = Pos + 1

		Char, Pos, Err = SkipWhitespace( JSONString, Context )
		if not Char then
			return nil, Pos, Err
		end

		local State, Pos, Err = PushStateFromChar( JSONString, Char, Pos, Context )
		if not State then
			return nil, Pos, Err
		end

		local Table = Context.Value[ Context.ValueCount ]
		if State ~= STATE_OBJECT and State ~= STATE_ARRAY then
			Context.Pos = Pos

			local Value, Pos, Err = Parsers[ State ]( JSONString, Context )
			if Err then
				return nil, Pos, Err
			end

			Table[ Key ] = Value

			Char, Pos, Err = SkipWhitespace( JSONString, Context )
			if not Char then
				return nil, Pos, Err
			end

			if Char == "," then
				-- Value followed by comma, expect more key-value pairs.
				Context.Pos = Pos + 1
				return true
			end

			if Char == "}" then
				Context.Pos = Pos + 1
				return PopTableState( JSONString, Context )
			end

			return nil, Pos, StringFormat(
				"'}' expected to end object at line %d, column %d", GetLineColumn( JSONString, Pos )
			)
		end

		Context.Pos = Pos + 1

		local Value = setmetatable( TableNew( 10, 10 ), MetaTables[ State ] )
		Table[ Key ] = Value

		return PushValue( Context, Value )
	end,
	[ STATE_ARRAY ] = function( JSONString, Context )
		local Char, Pos, Err = SkipWhitespace( JSONString, Context )
		if not Char then
			return nil, Pos, Err
		end

		if Char == "]" then
			Context.Pos = Pos + 1
			return PopTableState( JSONString, Context )
		end

		local State, Pos, Err = PushStateFromChar( JSONString, Char, Pos, Context )
		if not State then
			return nil, Pos, Err
		end

		local Key = Context.Key[ Context.ValueCount ] + 1
		Context.Key[ Context.ValueCount ] = Key

		local Table = Context.Value[ Context.ValueCount ]
		if State ~= STATE_OBJECT and State ~= STATE_ARRAY then
			Context.Pos = Pos

			local Value, Pos, Err = Parsers[ State ]( JSONString, Context )
			if Err then
				return nil, Pos, Err
			end

			Table[ Key ] = Value

			Char, Pos, Err = SkipWhitespace( JSONString, Context )
			if not Char then
				return nil, Pos, Err
			end

			if Char == "," then
				-- Value followed by comma, expect more values.
				Context.Pos = Pos + 1
				return true
			end

			if Char == "]" then
				Context.Pos = Pos + 1
				return PopTableState( JSONString, Context )
			end

			return nil, Pos, StringFormat(
				"']' expected to end array at line %d, column %d", GetLineColumn( JSONString, Pos )
			)
		end

		Context.Pos = Pos + 1

		local Value = setmetatable( TableNew( 10, 10 ), MetaTables[ State ] )
		Table[ Key ] = Value

		return PushValue( Context, Value )
	end,
	[ STATE_STRING ] = function( JSONString, Context )
		local String, Pos, Err = ParseString( JSONString, Context )
		if not String then
			return nil, Pos, Err
		end
		return String
	end,
	[ STATE_LITERAL ] = function( JSONString, Context )
		local Pos = Context.Pos
		local Start, End = StringFind( JSONString, "^%a%w+", Pos )
		if Start then
			local Word = StringSub( JSONString, Start, End )

			Context.Pos = End + 1

			if Word == "true" then
				return true
			end

			if Word == "false" then
				return false
			end

			if Word == "null" then
				return nil
			end
		end

		return nil, Pos, StringFormat(
			"invalid literal value at line %d, column %d", GetLineColumn( JSONString, Pos )
		)
	end,
	[ STATE_NUMBER ] = function( JSONString, Context )
		local Pos = Context.Pos
		local Start, End = StringFind( JSONString, "^%-?[%d%.]+[eE]?[%+%-]?%d*", Pos )
		if Start then
			local Num = tonumber( StringSub( JSONString, Start, End ) )
			if Num then
				Context.Pos = End + 1
				return Num
			end
		end
		return nil, Pos, StringFormat(
			"invalid number at line %d, column %d", GetLineColumn( JSONString, Pos )
		)
	end
}

--[[
	Creates a decoder that can be invoked iteratively to decode JSON data.

	This can be helpful when dealing with excessively large JSON data to avoid blocking for a large amount of time.
	Callers are expected to keep calling the returned function until it returns true, at which point either decoding
	has completed successfully, or invalid JSON was encountered.

	Note that this decoder is stricter than DKJSON in the following ways:
	* Commas must be present between all key-values in an object, and all values in an array.
		* DKJSON accepts JSON like {"key1": true "key2": false}, this does not.
		* Commas left at the end of an object/array do not result in an error however (as with DKJSON).
	* An object without keys is not parsed as an array (e.g. {"test",true} is an error, not ["test",true]).

	Input: A JSON string to be decoded.
	Output: A function that, when called returns either:
		* false - if decoding has not yet completed.
		* true, decoded value or nil, byte position, error description (if an error occurred).
]]
function JSON.DecoderFromString( JSONString )
	local Context = {
		State = TableNew( 5, 0 ),
		StateCount = 0,
		Value = TableNew( 5, 0 ),
		ValueCount = 0,
		Key = TableNew( 5, 0 ),
		UnescapedStrings = setmetatable( TableNew( 0, 30 ), UnescapeStringCache ),
		Pos = 1
	}

	local State = STATE_INIT
	local StringLength = #JSONString
	return function()
		local OK, Pos, Err = Parsers[ State ]( JSONString, Context )
		if Err then
			return true, nil, Pos, Err
		end

		State = Context.State[ Context.StateCount ]

		if not State or Context.Pos > StringLength then
			return true, Context.RootValue
		end

		return false
	end
end

return JSON
