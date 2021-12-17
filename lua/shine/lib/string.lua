--[[
	Shine string library.
]]

local Floor = math.floor
local StringFind = string.find
local StringFormat = string.format
local StringGMatch = string.gmatch
local StringGSub = string.gsub
local StringLen = string.len
local StringLower = string.lower
local StringMatch = string.match
local StringSub = string.sub
local StringUpper = string.upper
local TableConcat = table.concat

--[[
	Returns true if the given string ends with the given suffix.
]]
function string.EndsWith( String, Suffix )
	local SuffixLength = StringLen( Suffix )
	local StringLength = StringLen( String )

	return StringSub( String, StringLength - SuffixLength + 1 ) == Suffix
end

--[[
	Returns true if the given string starts with the given prefix.
]]
function string.StartsWith( String, Prefix )
	return StringSub( String, 1, StringLen( Prefix ) ) == Prefix
end

--[[
	Returns the given string with its first character in upper case.

	Note that this is *not* UTF-8 aware.
]]
function string.Capitalise( String )
	return StringUpper( StringSub( String, 1, 1 ) )..StringSub( String, 2 )
end

do
	local PatternReplacements = {
		[ "(" ] = "%(",
		[ ")" ] = "%)",
		[ "." ] = "%.",
		[ "%" ] = "%%",
		[ "+" ] = "%+",
		[ "-" ] = "%-",
		[ "*" ] = "%*",
		[ "?" ] = "%?",
		[ "[" ] = "%[",
		[ "]" ] = "%]",
		[ "^" ] = "%^",
		[ "$" ] = "%$",
		[ "\0" ] = "%z"
	}

	--[[
		Returns the given string with all Lua pattern control characters escaped.
	]]
	function string.PatternSafe( String )
		return StringGSub( String, ".", PatternReplacements )
	end
end

--[[
	Splits the given string by the given pattern.

	Inputs:
		1. String to split.
		2. Pattern to split with.
		3. Optional flag to indicate that the separator should not be interpreted as a pattern.
	Output:
		Table containing strings separated by the given pattern.
]]
function string.Explode( String, Separator, NoPattern )
	local Ret = {}

	local LastEnd = 1
	for i = 1, #String do
		local Start, End = StringFind( String, Separator, LastEnd, NoPattern )
		if not Start then break end

		Ret[ i ] = StringSub( String, LastEnd, Start - 1 )
		LastEnd = End + 1
	end

	Ret[ #Ret + 1 ] = StringSub( String, LastEnd )

	return Ret
end

do
	local Shine = Shine

	local TimeFuncs
	local GetAsString
	local JoinMultiResults
	local GetSeparator

	if Server then
		GetAsString = function( Value, Singular, Plural )
			return StringFormat( "%i %s", Value, Value == 1 and Singular or Plural )
		end

		JoinMultiResults = function( Before, After )
			return StringFormat( "%s and %s", Before, After )
		end

		GetSeparator = function()
			return ", "
		end

		TimeFuncs = {
			function( Time ) return Floor( Time % 60 ), "second", "seconds" end,
			function( Time ) return Floor( Time / 60 ) % 60, "minute", "minutes" end,
			function( Time ) return Floor( Time / 3600 ) % 24, "hour", "hours" end,
			function( Time ) return Floor( Time / 86400 ) % 7, "day", "days" end,
			function( Time ) return Floor( Time / 604800 ), "week", "weeks" end
		}
	else
		local function GetPhrase( Phrase )
			return Shine.Locale:GetPhrase( "Core", Phrase )
		end

		GetAsString = function( Value, Singular, Plural )
			return Shine.Locale:GetInterpolatedPhrase( "Core", "TIME_VALUE", {
				Value = Value,
				TimeUnit = Shine.Locale:GetInterpolatedPhrase( "Core", Singular, {
					Value = Value
				} )
			} )
		end

		JoinMultiResults = function( Before, After )
			return Shine.Locale:GetInterpolatedPhrase( "Core", "TIME_SENTENCE", {
				Before = Before,
				After = After
			} )
		end

		GetSeparator = function()
			return GetPhrase( "TIME_SEPARATOR" )
		end

		TimeFuncs = {
			function( Time ) return Floor( Time % 60 ), "SECOND" end,
			function( Time ) return Floor( Time / 60 ) % 60, "MINUTE" end,
			function( Time ) return Floor( Time / 3600 ) % 24, "HOUR" end,
			function( Time ) return Floor( Time / 86400 ) % 7, "DAY" end,
			function( Time ) return Floor( Time / 604800 ), "WEEK" end
		}
	end

	local NumTimes = #TimeFuncs

	--[[
		Converts a time value into a "nice" time string.

		Input: Time value in seconds.
		Output: "Nice" time string, e.g 65 -> "1 minute and 5 seconds".
	]]
	function string.TimeToString( Time )
		if Time < 1 then return GetAsString( TimeFuncs[ 1 ]( 0 ) ) end

		local Result = {}
		local Count = 0
		for i = NumTimes, 1, -1 do
			local Value, Singular, Plural = TimeFuncs[ i ]( Time )

			if Value > 0 then
				Count = Count + 1
				Result[ Count ] = GetAsString( Value, Singular, Plural )
			end
		end

		if Count == 1 then
			return Result[ 1 ]
		end

		local Before = TableConcat( Result, GetSeparator(), 1, Count - 1 )
		local After = Result[ Count ]

		return JoinMultiResults( Before, After )
	end
end

function string.TimeToDuration( Time )
	if Time == 0 then return "permanently" end

	return StringFormat( "for %s", string.TimeToString( Time ) )
end

--[[
	Converts a time value to a digital representation in minutes:seconds.

	Input: Time value in seconds.
	Output: Digital time.
]]
function string.DigitalTime( Time )
	if Time <= 0 then return "00:00" end

	local Seconds = Floor( Time % 60 )
	local Minutes = Floor( Time / 60 )

	return StringFormat( "%.2i:%.2i", Minutes, Seconds )
end

do
	local tonumber = tonumber

	local Times = {
		sec = 1, secs = 1, s = 1, second = 1, seconds = 1,
		m = 60,	minute = 60, minutes = 60, min = 60, mins = 60,
		h = 3600, hr = 3600, hrs = 3600, hour = 3600, hours = 3600,
		d = 86400, day = 86400, days = 86400,
		w = 604800, week = 604800, weeks = 604800
	}

	--[[
		Converts a string of time magnitude -> time unit to a time value in seconds.

		Input: String containing some kind of time information.
		Output: Time value the string represents in seconds.
	]]
	function string.ToTime( String )
		local Time = 0

		for Amount, Unit in StringGMatch( StringLower( String ), "([%-%d%.]+)%s-([a-z]+)" ) do
			local Magnitude = Times[ Unit ]
			if Magnitude then
				Amount = tonumber( Amount )
				if Amount then
					Time = Time + Amount * Magnitude
				end
			end
		end

		return Time
	end
end

do
	local OSDate = os.date
	local OSTime = os.time
	local tonumber = tonumber

	local LOCAL_DATE_TIME = "^(%d+)%-(%d+)%-(%d+)[T ](%d+):(%d+):?(%d*)$"
	local LOCAL_TIME = "^T?(%d+):(%d+):?(%d*)$"

	--[[
		Parses the given string into a timestamp.

		Format should be one of (where seconds are optional):
		YYYY-MM-ddTHH:mm:ss
		YYYY-MM-dd HH:mm:ss
		THH:mm:ss
		HH:mm:ss

		If the string is a full date-time, the timestamp will use the given year/month/day,
		otherwise, it will use the current local time's date.
	]]
	function string.ParseLocalDateTime( Time, FallbackDate )
		FallbackDate = FallbackDate or OSDate( "*t" )

		local IsDateTime = true
		local Year, Month, Day, Hour, Minute, Second = StringMatch( Time, LOCAL_DATE_TIME )
		if not Year then
			IsDateTime = false

			Year = FallbackDate.year
			Month = FallbackDate.month
			Day = FallbackDate.day

			Hour, Minute, Second = StringMatch( Time, LOCAL_TIME )
		end

		if not Hour then
			return nil, "invalid date/time format"
		end

		return OSTime( {
			year = tonumber( Year ),
			month = tonumber( Month ),
			day = tonumber( Day ),
			hour = tonumber( Hour ),
			min = tonumber( Minute ),
			sec = tonumber( Second ) or 0
		} ), IsDateTime
	end
end

do
	local StringExplode = string.Explode
	local StringGSub = string.gsub
	local TableRemove = table.remove
	local tostring = tostring

	local Transformers = {
		Lower = function( FormatArg )
			return string.UTF8Lower( FormatArg )
		end,
		Upper = function( FormatArg )
			return string.UTF8Upper( FormatArg )
		end,
		Format = function( FormatArg, TransformArg )
			return StringFormat( TransformArg, FormatArg )
		end,
		Abs = math.abs,

		-- Adds a full-stop at the end of the given value if it does not end with a sentence terminating character.
		-- Also trims any whitespace from the end of the value.
		EnsureSentence = function( FormatArg, TransformArg )
			return StringGSub(
				StringGSub( FormatArg, "[,:;]?%s*$", "" ),
				"([^%.!%?])%s*$",
				"%1."
			)
		end
	}
	string.InterpolateTransformers = Transformers

	do
		--[[
			Transforms a number into a phrase based on pluralisation rules.

			For example:
				- singular|plural with English definition: n == 1 and 1 or 2
				- singular|between 2 and 4|more than 4 with definition:
				( n == 1 and 1 ) or ( ( n >= 2 and n <= 4 ) and 2 ) or 3
		]]
		Transformers.Pluralise = function( FormatArg, TransformArg, LangDef )
			local Args = StringExplode( TransformArg, "|", true )
			return Args[ LangDef.GetPluralForm( FormatArg ) ] or Args[ #Args ]
		end
	end

	local function ApplyInterpolationTransformer( Parameter, FormatArgs, LangDef )
		local Args = StringExplode( Parameter, ":", true )
		local Transformation = Args[ 2 ]

		if not Transformation then
			return tostring( FormatArgs[ Parameter ] or Parameter ), Parameter
		end

		local ArgName = TableRemove( Args, 1 )
		local Ret = FormatArgs[ ArgName ]

		for i = 1, #Args, 2 do
			local Transformer = Args[ i ]
			local TransformerArgs = Args[ i + 1 ]

			Ret = Transformers[ Transformer ]( Ret, TransformerArgs, LangDef )
		end

		return tostring( Ret ), ArgName
	end
	string.ApplyInterpolationTransformer = ApplyInterpolationTransformer

	--[[
		Provides a way to format strings by placing arguments at any point in the
		string enclosed in {}.

		Example:
		string.Interpolate( "Cake is {Opinion}!", { Opinion = "great" } )
		-> "Cake is great!"

		Also supports UTF-8 aware upper and lower case, and formatting arguments:
		string.Interpolate( "{Thing} is {Opinion:Upper} x {Scale:Format:%.2f}!", {
			Thing = "Cake",
			Opinion = "great",
			Scale = 2.5
		} )
		-> "Cake is GREAT x 2.50!"
	]]
	function string.Interpolate( String, FormatArgs, LangDef )
		return ( StringGSub( String, "{(.-)}", function( Match )
			return ( ApplyInterpolationTransformer( Match, FormatArgs, LangDef ) )
		end ) )
	end
end

do
	local StringExplode = string.Explode
	local StringUpper = string.upper

	local function ParseCamelCase( Value, Segments )
		for UpperCase, LowerCase in StringGMatch( Value, "(%u+)(%U*)" ) do
			if #LowerCase == 0 then
				-- Preserve the upper case nature of the value.
				Segments[ #Segments + 1 ] = UpperCase
			else
				if #UpperCase > 1 then
					-- Assume that acronyms always end 1 character before the end of an upper case sequence.
					Segments[ #Segments + 1 ] = StringSub( UpperCase, 1, -2 )
					UpperCase = StringSub( UpperCase, -1 )
				end

				Segments[ #Segments + 1 ] = StringLower( UpperCase..LowerCase )
			end
		end
		return Segments
	end

	string.CaseFormatType = {
		UPPER_CAMEL = {
			Parse = function( Value )
				return ParseCamelCase( Value, {} )
			end,
			Format = function( Segments )
				for i = 1, #Segments do
					Segments[ i ] = StringUpper( StringSub( Segments[ i ], 1, 1 ) )..StringSub( Segments[ i ], 2 )
				end
				return TableConcat( Segments )
			end
		},
		LOWER_CAMEL = {
			Parse = function( Value )
				local Segments = {}
				local FirstSegment = StringMatch( Value, "^(%U+)" )
				if FirstSegment then
					Segments[ 1 ] = FirstSegment
					Value = StringSub( Value, #FirstSegment + 1 )
				end
				return ParseCamelCase( Value, Segments )
			end,
			Format = function( Segments )
				Segments[ 1 ] = StringLower( Segments[ 1 ] )
				for i = 2, #Segments do
					Segments[ i ] = StringUpper( StringSub( Segments[ i ], 1, 1 ) )..StringSub( Segments[ i ], 2 )
				end
				return TableConcat( Segments )
			end
		},
		UPPER_UNDERSCORE = {
			Parse = function( Value )
				return StringExplode( StringLower( Value ), "_", true )
			end,
			Format = function( Segments )
				for i = 1, #Segments do
					Segments[ i ] = StringUpper( Segments[ i ] )
				end
				return TableConcat( Segments, "_" )
			end
		},
		LOWER_UNDERSCORE = {
			Parse = function( Value )
				return StringExplode( Value, "_", true )
			end,
			Format = function( Segments )
				for i = 1, #Segments do
					Segments[ i ] = StringLower( Segments[ i ] )
				end
				return TableConcat( Segments, "_" )
			end
		},
		HYPHEN = {
			Parse = function( Value )
				return StringExplode( Value, "-", true )
			end,
			Format = function( Segments )
				for i = 1, #Segments do
					Segments[ i ] = StringLower( Segments[ i ] )
				end
				return TableConcat( Segments, "-" )
			end
		}
	}

	--[[
		Transforms the case of the given value from one case format to another.

		Example:
		string.TransformCase(
			"SomeConfigKey", string.CaseFormatType.UPPER_CAMEL, string.CaseFormatType.UPPER_UNDERSCORE
		)
		-> "SOME_CONFIG_KEY"
	]]
	function string.TransformCase( Value, FromCaseFormat, ToCaseFormat )
		local Segments = FromCaseFormat.Parse( Value )
		return ToCaseFormat.Format( Segments )
	end
end

do
	local BAnd = bit.band
	local BOr = bit.bor
	local LShift = bit.lshift
	local RShift = bit.rshift

	local StringByte = string.byte
	local StringChar = string.char

	local Base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='
	local EqualsByte = StringByte( "=" )

	--[[
		Encodes the given string into base 64 form with no line breaks.
	]]
	function string.ToBase64( String )
		local Out = {}

		local Count = 0
		for i = 1, #String, 3 do
			Count = Count + 1

			local Byte1, Byte2, Byte3 = StringByte( String, i, i + 2 )
			Out[ Count ] = StringChar(
				-- First 6 bits of the first byte
				StringByte( Base64Chars, RShift( Byte1, 2 ) + 1 ),
				-- Last 2 bits of the first byte, and first 4 bits of the second byte
				StringByte(
					Base64Chars,
					BOr(
						LShift( BAnd( Byte1, 0x3 ), 4 ),
						RShift( Byte2 or 0, 4 )
					) + 1
				),
				-- Last 4 bits of the second byte, and first 2 bits of the 3rd byte
				Byte2 and StringByte(
					Base64Chars,
					BOr(
						LShift( BAnd( Byte2, 0xF ), 2 ),
						RShift( Byte3 or 0, 6 )
					) + 1
				) or EqualsByte,
				-- Last 6 bits of the third byte
				Byte3 and StringByte(
					Base64Chars,
					BAnd( Byte3, 0x3F ) + 1
				) or EqualsByte
			)
		end

		return TableConcat( Out )
	end

	local InverseLookup = {}
	for i = 1, #Base64Chars do
		InverseLookup[ StringByte( Base64Chars, i ) ] = i - 1
	end

	--[[
		Decodes the given string from base 64, assuming no line breaks.
	]]
	function string.FromBase64( String )
		local Out = {}

		local Count = 0
		for i = 1, #String, 4 do
			local Byte1, Byte2, Byte3, Byte4 = StringByte( String, i, i + 3 )
			Byte1 = InverseLookup[ Byte1 ]
			Byte2 = InverseLookup[ Byte2 ]
			Byte3 = InverseLookup[ Byte3 ]
			Byte4 = InverseLookup[ Byte4 ]

			-- Take all 6 bits from byte 1, and the first 2 of byte 2
			Out[ Count + 1 ] = StringChar(
				BOr( LShift( Byte1, 2 ), RShift( Byte2, 4 ) )
			)

			-- If padded with ==, then only 1 byte can be extracted.
			if Byte3 >= 63 then break end

			-- Take the last 4 bits of byte 2, and the first 4 of byte 3.
			Out[ Count + 2 ] = StringChar(
				BOr( LShift( BAnd( Byte2, 0xF ), 4 ), RShift( Byte3, 2 ) )
			)

			-- If padded with =, then only 2 bytes can be extracted.
			if Byte4 >= 63 then break end

			-- Take the last 2 bits from byte 3, and the all 6 from byte 4.
			Out[ Count + 3 ] = StringChar(
				BOr( LShift( BAnd( Byte3, 0x3 ), 6 ), Byte4 )
			)

			Count = Count + 3
		end

		return TableConcat( Out )
	end
end

do
	local Max = math.max
	local tonumber = tonumber

	--[[
		Converts a hexidecimal string (with or without an "0x" prefix) into a number.

		Unlike tonumber(), this isn't limited to 32bits, and instead uses the full double precision float range.

		Input: Hex string to convert.
		Output: The numeric value represented by the given hexidecimal value, or nil if the string can't be converted.
	]]
	function string.HexToNumber( Hex )
		local Mult = 1
		local Sum = 0

		-- Operate in 8 byte chunks (representing 4 byte uints) as that's the limit of tonumber() for base 16.
		for i = #Hex, 1, -8 do
			local Char = StringSub( Hex, Max( i - 7, 1 ), i )
			local Factor = tonumber( Char, 16 )
			if not Factor then return nil end

			Sum = Sum + Mult * Factor
			Mult = Mult * ( 16 ^ 8 )
		end

		return Sum
	end
end
