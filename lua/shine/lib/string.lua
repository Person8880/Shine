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

function string.TimeToString( Time )
	if Time < 1 then return "0 seconds" end
	
	local Seconds = Floor( Time % 60 )
	local Minutes = Time / 60
	local Hours = Minutes / 60
	local Days = Hours / 24
	local Weeks = Days / 7

	local FloorMins = Floor( Minutes )
	local FloorHours = Floor( Hours )
	local FloorDays = Floor( Days )
	local FloorWeeks = Floor( Weeks )

	if FloorHours >= 1 then FloorMins = FloorMins % 60 end
	if FloorDays >= 1 then FloorHours = FloorHours % 24 end
	if FloorWeeks >= 1 then FloorDays = FloorDays % 7 end

	local Strings = {}

	if FloorWeeks >= 1 then
		Strings[ #Strings + 1 ] = FloorWeeks == 1 and "1 week" or FloorWeeks.." weeks"
	end
	if FloorDays >= 1 then
		Strings[ #Strings + 1 ] = FloorDays == 1 and "1 day" or FloorDays.." days"
	end
	if FloorHours >= 1 then
		Strings[ #Strings + 1 ] = FloorHours == 1 and "1 hour" or FloorHours.." hours"
	end
	if FloorMins >= 1 then
		Strings[ #Strings + 1 ] = FloorMins == 1 and "1 minute" or FloorMins.." minutes"
	end
	if Seconds >= 1 then
		Strings[ #Strings + 1 ] = Seconds == 1 and "1 second" or Seconds.." seconds"
	end

	if #Strings == 1 then
		return Strings[ 1 ]
	end

	local FinalString = TableConcat( Strings, ", ", 1, #Strings - 1 )

	return StringFormat( "%s and %s", FinalString, Strings[ #Strings ] )
end

function string.DigitalTime( Time )
	if Time <= 0 then return "00:00" end
	
	local Seconds = Floor( Time % 60 )
	local Minutes = Floor( Time / 60 )

	return StringFormat( "%.2i:%.2i", Minutes, Seconds )
end
