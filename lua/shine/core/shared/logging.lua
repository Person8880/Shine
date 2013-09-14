local StringFormat = string.format

local DebugFile = "config://shine\\DebugLog.txt"

local ErrorQueue = {}
local Reported = {}

if Server then
	local URL = "http://5.39.89.152/shine/errorreport.php"

	local TableConcat = table.concat
	local TableEmpty = table.Empty

	Shine.Hook.Add( "EndGame", "ReportQueuedErrors", function()
		if not Shine.Config.ReportErrors then return end
		
		local PostData = TableConcat( ErrorQueue, "\n" )

		Shared.SendHTTPRequest( URL, "POST", { error = PostData, blehstuffcake = "enihs" }, function() end )
	
		TableEmpty( ErrorQueue )
	end )
end

--[[
	Logs debug/error messages from hooks and timers.
]]
function Shine:DebugLog( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	if Server and String:sub( 1, 6 ) == "Error:" and self.Config.ReportErrors then
		local Start = String:find( "\n" )

		if Start then
			local Error = String:sub( 8, Start )

			if not Reported[ Error ] then
				Reported[ Error ] = true

				ErrorQueue[ #ErrorQueue + 1 ] = String
			end
		end
	end

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
