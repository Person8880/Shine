--[[
	Shine's logging system.
]]

local Shine = Shine

if Shine.Error then return end

local Build = Shared.GetBuildNumber()

Script.Load "lua/Utility.lua"

local Time = Shared.GetSystemTime
local Ceil = math.ceil
local Date = os and os.date
local Floor = math.floor
local StringFormat = string.format
local TableConcat = table.concat
local type = type

local MonthData = {
	{ Name = "January", Length = 31 },
	{ Name = "February", Length = 28, LeapLength = 29 },
	{ Name = "March", Length = 31 },
	{ Name = "April", Length = 30 },
	{ Name = "May", Length = 31 },
	{ Name = "June", Length = 30 },
	{ Name = "July", Length = 31 },
	{ Name = "August", Length = 31 },
	{ Name = "September", Length = 30 },
	{ Name = "October", Length = 31 },
	{ Name = "November", Length = 30 },
	{ Name = "December", Length = 31 }
}

local function GetDate( Logging )
	local Day, Month, Year

	--This old method is left for reference. Eventually I'll remove it.
	if Build < 249 or not Date then
		local SysTime = Time() + ( Shine.Config.TimeOffset * 3600 )

		Year = Floor( SysTime / 31557600 )
		local LeapYear = ( ( Year + 2 ) % 4 ) == 0

		local NumOfExtraDays = Floor( ( Year - 2 ) / 4 )

		local Days = Floor( ( SysTime / 86400 ) - ( Year * 365 ) - NumOfExtraDays )

		Year = Year + 1970

		Day = 0
		Month = 0
		local Sum = 0
		for i = 1, #MonthData do
			local CurMonth = MonthData[ i ]
			local Length = LeapYear and ( CurMonth.LeapLength or CurMonth.Length ) or CurMonth.Length

			Sum = Sum + Length

			if Days <= Sum then
				Day = Days - Sum + Length + ( LeapYear and 1 or 0 )
				Month = i
				break
			end
		end
	else
		Day = tonumber( Date( "%d" ) )
		Month = tonumber( Date( "%m" ) )
		Year = tonumber( Date( "%Y" ) )
	end

	local DateFormat = Shine.Config.DateFormat
	local Parsed = string.Explode( DateFormat, "-" )

	local FormatString = Logging and 
		"[%0"..#Parsed[ 1 ].."i:%0"..#Parsed[ 2 ].."i:%0"..#Parsed[ 3 ].."i]" 
		or "%0"..#Parsed[ 1 ].."i_%0"..#Parsed[ 2 ].."i_%0"..#Parsed[ 3 ].."i"

	local Elements = {}
	for i = 1, 3 do
		Elements[ i ] = ( Parsed[ i ]:find( "d" ) and Day ) or ( Parsed[ i ]:find( "m" ) and Month ) or ( Parsed[ i ]:find( "y" ) and tostring( Year ):sub( 5 - #Parsed[ i ], 4 ) )
	end

	return StringFormat( FormatString, Elements[ 1 ], Elements[ 2 ], Elements[ 3 ] )
end
Shine.GetDate = GetDate

local function GetTimeString()
	if Build >= 249 and Date then
		return Date( "[%H:%M:%S]" )
	end

	local SysTime = Time() + ( Shine.Config.TimeOffset * 3600 )
	local Seconds = Floor( SysTime % 60 )
	local Minutes = Floor( ( SysTime / 60 ) % 60 )
	local Hours = Floor( ( ( SysTime / 60 ) / 60 ) % 24 )
	
	return StringFormat( "[%02i:%02i:%02i]", Hours, Minutes, Seconds )
end
Shine.GetTimeString = GetTimeString

Shared.OldMessage = Shared.OldMessage or Shared.Message

--[[
	Fun fact for anyone reading, this thread started Shine:
	
	http://forums.unknownworlds.com/discussion/126283/time-in-log-files
	
	and this function was its first feature.
]]
function Shared.Message( String )
	return Shared.OldMessage( GetTimeString()..String )
end

local function GetCurrentLogFile()
	return Shine.Config.LogDir..GetDate()..".txt"
end

local LogMessages = {}

function Shine:LogString( String )
	if not self.Config.EnableLogging then return end

	LogMessages[ #LogMessages + 1 ] = GetTimeString()..String
end

function Shine:SaveLog()
	if not self.Config.EnableLogging then return end
	
	local String = TableConcat( LogMessages, "\n" )

	--This is dumb, but append mode appears to be broken.
	local OldLog, Err = io.open( GetCurrentLogFile(), "r" )

	local Data = ""

	if OldLog then
		Data = OldLog:read( "*all" )
		OldLog:close()
	end
	
	local LogFile, Err = io.open( GetCurrentLogFile(), "w+" )

	if not LogFile then
		Shared.Message( StringFormat( "Error writing to log file: %s", Err  ) )

		return
	end

	LogFile:write( Data, String, "\n" )

	LogFile:close()

	--Empty the logging table.
	for i = 1, #LogMessages do
		LogMessages[ i ] = nil
	end
end

--Periodically save the log file.
Shine.Hook.Add( "EndGame", "SaveLog", function()
	Shine:SaveLog()
end, -20 )

Shine.Hook.Add( "MapChange", "SaveLog", function()
	Shine:SaveLog()
end, -20 )

Shine.Timer.Create( "LogSave", 300, -1, function()
	Shine:SaveLog()
end )

function Shine:Print( String, Format, ... )
	String = Format and StringFormat( String, ... ) or String

	Shared.Message( String )

	self:LogString( String )
end

local function istable( Tab )
	return type( Tab ) == "table"
end

--[[
	Sends a chat message to the given player(s).
]]
function Shine:Notify( Player, Prefix, Name, String, Format, ... )
	local Message = Format and StringFormat( String, ... ) or String

	local MessageLength = #Message
	if MessageLength > kMaxChatLength then
		local Iterations = Ceil( MessageLength / kMaxChatLength )

		for i = 1, Iterations do
			self:Notify( Player, Prefix, Name, Message:sub( 1 + kMaxChatLength * ( i - 1 ), kMaxChatLength * i ) )
		end

		return
	end

	if istable( Player ) == "table" then
		local PlayerCount = #Player

		for i = 1, PlayerCount do
			local Ply = Player[ i ]
			
			Server.SendNetworkMessage( Ply, "Shine_Chat", self.BuildChatMessage( Prefix, Name, kTeamReadyRoom, kNeutralTeamType, Message ), true )
		end
	elseif Player and Player ~= "Console" then
		Server.SendNetworkMessage( Player, "Shine_Chat", self.BuildChatMessage( Prefix, Name, kTeamReadyRoom, kNeutralTeamType, Message ), true )
	elseif Player == "Console" then
		Shared.Message( Message )
	else
		local Players = self.GetAllClients()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_Chat", self.BuildChatMessage( Prefix, Name, kTeamReadyRoom, kNeutralTeamType, Message ), true )
		end
	end
end

--[[
	Sends a coloured notification to the given player(s).
]]
function Shine:NotifyColour( Player, R, G, B, String, Format, ... )
	local Message = Format and StringFormat( String, ... ) or String

	local MessageTable = {
		R = R,
		G = G,
		B = B,
		Message = Message,
		RP = 0,
		GP = 0,
		BP = 0,
		Prefix = ""
	}

	Message = Message:sub( 1, kMaxChatLength )

	if not Player then
		local Players = self.GetAllClients()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_ChatCol", MessageTable, true )
		end
	elseif istable( Player ) then
		for i = 1, #Player do
			local Ply = Player[ i ]

			if Ply then
				Server.SendNetworkMessage( Ply, "Shine_ChatCol", MessageTable, true )
			end
		end 
	else
		Server.SendNetworkMessage( Player, "Shine_ChatCol", MessageTable, true )
	end
end

--[[
	Sends a coloured notification to the given player(s), supporting a coloured prefix.
]]
function Shine:NotifyDualColour( Player, RP, GP, BP, Prefix, R, G, B, String, Format, ... )
	local Message = Format and StringFormat( String, ... ) or String

	local MessageTable = {
		R = R,
		G = G,
		B = B,
		Message = Message,
		RP = RP,
		GP = GP,
		BP = BP,
		Prefix = Prefix
	}

	Message = Message:sub( 1, kMaxChatLength )

	if not Player then
		local Players = self.GetAllClients()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_ChatCol", MessageTable, true )
		end
	elseif istable( Player ) then
		for i = 1, #Player do
			local Ply = Player[ i ]

			if Ply then
				Server.SendNetworkMessage( Ply, "Shine_ChatCol", MessageTable, true )
			end
		end 
	else
		Server.SendNetworkMessage( Player, "Shine_ChatCol", MessageTable, true )
	end
end

--[[
	An easy error message function.
]]
function Shine:NotifyError( Player, Message, Format, ... )
	self:NotifyDualColour( Player, 255, 0, 0, "[Error]", 255, 255, 255, Message, Format, ... )
end

local OldServerAdminPrint = ServerAdminPrint

local MaxPrintLength = 128

Shine.Hook.Add( "Think", "OverrideServerAdminPrint", function( Deltatime )
	--[[
		Rewrite ServerAdminPrint to not print to the server console when used, otherwise we'll get spammed with repeat prints when sending to lots of people at once.
	]]
	function ServerAdminPrint( Client, Message )
		if not Client then return end
		
		local MessageList = {}
		local Count = 1

		while #Message > MaxPrintLength do
			local Part = Message:sub( 0, MaxPrintLength )

			MessageList[ Count ] = Part
			Count = Count + 1

			Message = Message:sub( MaxPrintLength + 1 )
		end

		MessageList[ Count ] = Message
		
		for i = 1, #MessageList do
			Server.SendNetworkMessage( Client:GetControllingPlayer(), "ServerAdminPrint", { message = MessageList[ i ] }, true )
		end
	end

	Shine.Hook.Remove( "Think", "OverrideServerAdminPrint" )
end )

function Shine:AdminPrint( Client, String, Format, ... )
	self:Print( String, Format, ... )

	local Message = Format and StringFormat( String, ... ) or String

	local Admins = self:GetClientsForLog()

	for i = 1, #Admins do
		local Admin = Admins[ i ]
		if Admin ~= Client then
			ServerAdminPrint( Admin, Message )
		end
	end

	if not Client then return end
	
	return ServerAdminPrint( Client, Message )
end
