local StringFormat = string.format

local DebugFile = "config://shine\\DebugLog.txt"

--[[
	Logs debug/error messages from hooks and timers.
]]
function Shine:DebugLog( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	local File, Err = io.open( DebugFile, "r" )

	local Data = ""

	if File then
		Data = File:read( "*all" )
		File:close()
	end

	File, Err = io.open( DebugFile, "w+" )

	if not File then return end
	
	File:write( Data, String, "\n" )
	File:close()
end

function Shine:DebugPrint( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	Shared.Message( String )

	self:DebugLog( String )
end
