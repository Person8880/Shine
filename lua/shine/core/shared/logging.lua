--[[
	Error report handling.
]]

local StringFormat = string.format

do
	local Date = os.date
	local Writer
	if Client or Predict then
		Writer = function( Text )
			Print( "%s[Shine] %s", Date( "[%H:%M:%S]" ), Text )
		end
	else
		Writer = function( Text )
			Shine:Print( Text )
		end
	end

	Shine.Logger = Shine.Objects.Logger( Shine.Objects.Logger.LogLevel.INFO, Writer )
end

if Predict then
	function Shine:AddErrorReport()
		-- Ignored, predict VM can't send HTTP requests.
	end

	function Shine:DebugLog()
		-- Ignored, predict VM shouldn't be logging to a separate file.
	end
else
	local DebugFile = "config://shine/DebugLog.txt"

	local ErrorQueue = {}
	local Reported = {}

	local URL = "http://51.68.206.223/shine/errorreport.php"

	local BuildNumber = Shared.GetBuildNumber()
	local OS = jit and jit.os or "Unknown"

	local IsType = Shine.IsType
	local pcall = pcall
	local StringHexToNumber = string.HexToNumber
	local TableConcat = table.concat
	local TableEmpty = table.Empty
	local TableInsert = table.insert
	local tonumber = tonumber
	local tostring = tostring

	local function IsDedicatedServer()
		if Server then
			return Server.IsDedicated()
		end

		if IsType( GetGameInfoEntity, "function" ) then
			local GameInfo = GetGameInfoEntity()
			if GameInfo and IsType( GameInfo.GetIsDedicated, "function" ) and not GameInfo:GetIsDedicated() then
				return false
			end
		end

		return true
	end

	-- Force disable error reporting in listen servers as they tend to be used for development which creates noisy error
	-- reports. If an error is truly a problem it will show up on dedicated servers.
	local function IsErrorReportEnabled()
		-- Be a bit paranoid here, errors would disrupt the entire reporting system.
		local Success, IsDedicatedOrErr = pcall( IsDedicatedServer )
		if not Success then return true end

		return IsDedicatedOrErr
	end

	local function ReportErrors()
		if not Shine.Config.ReportErrors then return end
		if not IsErrorReportEnabled() then return end
		if #ErrorQueue == 0 then return end

		TableInsert(
			ErrorQueue,
			1,
			StringFormat(
				"Operating system: %s. Gamemode: %s. Build number: %s.",
				OS,
				Shine.GetGamemode(),
				BuildNumber
			)
		)

		if Server then
			local ModCount = Server.GetNumActiveMods()
			local Mods = {}
			for i = 1, ModCount do
				Mods[ i ] = tostring( StringHexToNumber( Server.GetActiveModId( i ) ) )
			end

			TableInsert( ErrorQueue, 2, "Installed mods: "..TableConcat( Mods, ", " ) )
		end

		local PostData = TableConcat( ErrorQueue, "\n" )

		Shared.SendHTTPRequest( URL, "POST", { error = PostData, blehstuffcake = "enihs" } )

		TableEmpty( ErrorQueue )
	end

	if Server then
		Shine.Hook.Add( "EndGame", "ReportQueuedErrors", ReportErrors )
	end

	local ErrorReportTimer

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
		if not IsErrorReportEnabled() then return end
		if Reported[ BaseError ] then return end

		Reported[ BaseError ] = true

		local String

		if Extra then
			local ExtraString = Format and StringFormat( Extra, ... ) or Extra

			String = StringFormat( "%s\n%s", BaseError, ExtraString )
		else
			String = BaseError
		end

		ErrorQueue[ #ErrorQueue + 1 ] = String

		-- We cannot send error reports on disconnect/map change anymore due to HTTP requests being cancelled,
		-- thus we need to send errors as soon as possible after they occur to avoid them being lost.
		-- We debounce to ensure we catch a sequence of errors in a single request.
		ErrorReportTimer = ErrorReportTimer or Shine.Timer.Simple( 1, function()
			ErrorReportTimer = nil
			ReportErrors()
		end )
		ErrorReportTimer:Debounce()
	end

	--[[
		Logs debug/error messages from hooks and timers.
	]]
	function Shine:DebugLog( String, Format, ... )
		if not self.Config.DebugLogging then return end

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
end

function Shine:DebugPrint( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	Shared.Message( String )

	self:DebugLog( String )
end
