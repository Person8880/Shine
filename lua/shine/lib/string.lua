--[[
	Shine string library.
]]

local Floor = math.floor
local StringFind = string.find
local StringFormat = string.format
local StringSub = string.sub
local TableConcat = table.concat

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

function string.DigitalTime( Time )
	if Time <= 0 then return "00:00" end
	
	local Seconds = Floor( Time % 60 )
	local Minutes = Floor( Time / 60 )

	return StringFormat( "%.2i:%.2i", Minutes, Seconds )
end
