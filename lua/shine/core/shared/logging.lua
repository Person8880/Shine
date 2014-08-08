local StringFormat = string.format

local DebugFile = "config://shine/DebugLog.txt"

local ErrorQueue = {}
local Reported = {}

local URL = "http://5.39.89.152/shine/errorreport.php"

local OS = jit and jit.os or "Unknown"

local next = next
local TableConcat = table.concat
local TableEmpty = table.Empty

local function ReportErrors()
	if not Shine.Config.ReportErrors then return end
	if not next( ErrorQueue ) then return end
	
	local PostData = TableConcat( ErrorQueue, "\n" )
	PostData = PostData:sub( 1, 10240 )

	Shared.SendHTTPRequest( URL, "POST", { error = PostData, blehstuffcake = "enihs" }, function() end )

	TableEmpty( ErrorQueue )
end

if Server then
	Shine.Hook.Add( "EndGame", "ReportQueuedErrors", ReportErrors )
elseif Client then
	Shine.Hook.Add( "ClientDisconnected", "ReportQueuedErrors", ReportErrors )
end

--[[
	Adds an error to be reported.

	Inputs:
		1. The base error message, this should be what the error function from xpcall receives,
		or a string that defines the error so we don't repeat report it in a session.
		2. Extra information string.
		3. Should the extra string be formatted?
		4. Args to add to the formatting of the extra string.
]]
function Shine:AddErrorReport( BaseError, Extra, Format, ... )
	if not self.Config.ReportErrors then return end
	if Reported[ BaseError ] then return end

	Reported[ BaseError ] = true

	local String

	if Extra then
		local ExtraString = Format and StringFormat( Extra, ... ) or Extra

		String = StringFormat( "%s.\n%s", BaseError, ExtraString )
	else
		String = BaseError
	end

	if #ErrorQueue == 0 then
		ErrorQueue[ 1 ] = StringFormat( "Operating system: %s.", OS )
	end

	ErrorQueue[ #ErrorQueue + 1 ] = String
end

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

	--If the file gets too big, empty it and start again.
	if #Data > 51200 then
		Data = ""
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
