--[[
	Shine's logging system.
]]

local Shine = Shine

local Ceil = math.ceil
local Date = os.date
local Floor = math.floor
local StringFormat = string.format
local TableConcat = table.concat
local type = type

--Geez what was I thinking with that old method...
local function GetDate( Logging )
	local DateFormat = Shine.Config.DateFormat
	local FormatString = DateFormat:gsub( "(d+)", "%%d" ):gsub( "(m+)", "%%m" )

	if FormatString:find( "yyyy" ) then
		FormatString = FormatString:gsub( "(y+)", "%%Y" )
	else
		FormatString = FormatString:gsub( "(y+)", "%%y" )
	end

	return Date( FormatString )
end
Shine.GetDate = GetDate

local function GetTimeString()
	return Date( "[%H:%M:%S]" )
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
	return StringFormat( "%s%s.txt", Shine.Config.LogDir, GetDate() )
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

local IsType = Shine.IsType

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

	if IsType( Player, "table" ) then
		local PlayerCount = #Player

		for i = 1, PlayerCount do
			local Ply = Player[ i ]
			
			Server.SendNetworkMessage( Ply, "Shine_Chat",
				self.BuildChatMessage( Prefix, Name, kTeamReadyRoom, kNeutralTeamType, Message ), true )
		end
	elseif Player and Player ~= "Console" then
		Server.SendNetworkMessage( Player, "Shine_Chat",
			self.BuildChatMessage( Prefix, Name, kTeamReadyRoom, kNeutralTeamType, Message ), true )
	elseif Player == "Console" then
		Shared.Message( Message )
	else
		local Players = self.GetAllClients()

		for i = 1, #Players do
			Server.SendNetworkMessage( Players[ i ], "Shine_Chat",
				self.BuildChatMessage( Prefix, Name, kTeamReadyRoom, kNeutralTeamType, Message ), true )
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
	elseif IsType( Player, "table" ) then
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
	elseif IsType( Player, "table" ) then
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
		Rewrite ServerAdminPrint to not print to the server console when used,
		otherwise we'll get spammed with repeat prints when sending to lots of people at once.
	]]
	function ServerAdminPrint( Client, Message )
		if not Client then return end
		
		local MessageList = {}
		local Count = 1

		while #Message > MaxPrintLength do
			local Part = Message:sub( 0, MaxPrintLength - 1 )

			MessageList[ Count ] = Part
			Count = Count + 1

			Message = Message:sub( MaxPrintLength )
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
