--[[
	Shine string library.
]]

local Floor = math.floor
local StringFind = string.find
local StringFormat = string.format
local StringSub = string.sub
local TableConcat = table.concat

--[[
	Splits the given string by the given pattern.

	Inputs:
		1. String to split.
		2. Pattern to split with.
	Output:
		Table containing strings separated by the given pattern.
]]
function string.Explode( String, Pattern )
	local Ret = {}
	local FindPattern = "(.-)"..Pattern
	local LastEnd = 1

	local Count = 0

	local Start, End, Found = StringFind( String, FindPattern )
	while Start do
		if Start ~= 1 or Found ~= "" then
			Count = Count + 1
			Ret[ Count ] = Found
		end

		LastEnd = End + 1
		Start, End, Found = StringFind( String, FindPattern, LastEnd )
	end

	if LastEnd <= #String then
		Found = StringSub( String, LastEnd )
		Count = Count + 1
		Ret[ Count ] = Found
	end

	return Ret
end

do
	local TimeFuncs = {
		function( Time ) return Floor( Time % 60 ), "second" end,
		function( Time ) return Floor( Time / 60 ) % 60, "minute" end,
		function( Time ) return Floor( Time / 3600 ) % 24, "hour" end,
		function( Time ) return Floor( Time / 86400 ) % 7, "day" end,
		function( Time ) return Floor( Time / 604800 ), "week" end
	}
	local NumTimes = #TimeFuncs

	--[[
		Converts a time value into a "nice" time string.

		Input: Time value in seconds.
		Output: "Nice" time string, e.g 65 -> "1 minute and 5 seconds".
	]]
	function string.TimeToString( Time )
		if Time < 1 then return "0 seconds" end

		local Result = {}
		local Count = 0
		for i = NumTimes, 1, -1 do
			local Value, String = TimeFuncs[ i ]( Time )

			if Value > 0 then
				Count = Count + 1
				Result[ Count ] = StringFormat( "%i %s%s", Value, String,
					Value > 1 and "s" or "" )
			end
		end

		if Count == 1 then
			return Result[ 1 ]
		end

		return StringFormat( "%s and %s", TableConcat( Result, ", ", 1, Count - 1 ),
			Result[ Count ] )
	end
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
	local StringGSub = string.gsub
	local StringLower = string.lower
	local tonumber = tonumber

	local Times = {
		sec = 1,
		secs = 1,
		s = 1,
		second = 1,
		seconds = 1,
		m = 60,
		minute = 60,
		minutes = 60,
		min = 60,
		mins = 60,
		h = 3600,
		hour = 3600,
		hours = 3600,
		d = 86400,
		day = 86400,
		days = 86400,
		w = 604800,
		week = 604800,
		weeks = 604800
	}

	--[[
		Converts a string of time magnitude -> time unit to a time value in seconds.

		Input: String containing some kind of time information.
		Output: Time value the string represents in seconds.
	]]
	function string.ToTime( String )
		local Time = 0

		StringGSub( StringLower( String ), "([%-%d%.]+)%s-([a-zA-Z]+)", function( Amount, Unit )
			local Magnitude = Times[ Unit ]
			if not Magnitude then return "" end

			Amount = tonumber( Amount )
			if not Amount then return "" end
			Time = Time + Amount * Magnitude

			return ""
		end )

		return Time
	end
end
