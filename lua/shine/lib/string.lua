--[[
	Shine string library.
]]

local Floor = math.floor
local StringFormat = string.format

--Thank you: http://lua-users.org/wiki/SplitJoin
function string.Explode( str, pat )
	local t = {}
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			t[ #t + 1 ] = cap
		end
		last_end = e+1
		s, e, cap = str:find(fpat, last_end)
	end
	if last_end <= #str then
		cap = str:sub(last_end)
		t[ #t + 1 ] = cap
	end
	return t
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

	return StringFormat( "%s%s%s%s%s%s%s%s%s", 
		( FloorWeeks == 1 and "1 week" ) or ( FloorWeeks > 1 and FloorWeeks.." weeks" ) or "",
		FloorWeeks ~= 0 and ( FloorDays ~= 0 or FloorHours ~= 0 or FloorMins ~= 0 or Seconds ~= 0 ) and ", " or "",
		( FloorDays == 1 and "1 day" ) or ( FloorDays > 1 and FloorDays.." days" ) or "",
		FloorDays ~= 0 and ( FloorHours ~= 0 or FloorMins ~= 0 or Seconds ~= 0 ) and ", " or "",
		( FloorHours == 1 and "1 hour" ) or ( FloorHours > 1 and FloorHours.." hours" ) or "",
		FloorHours ~= 0 and ( FloorMins ~= 0 or Seconds ~= 0 ) and ", " or "",
		( FloorMins == 1 and "1 minute" ) or ( FloorMins > 1 and FloorMins.." minutes" ) or "",
		Seconds ~= 0 and FloorMins ~= 0 and " and " or "",
		( Seconds == 1 and "1 second" ) or ( Seconds > 1 and Seconds.." seconds" ) or ""
	)
end
