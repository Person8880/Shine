--[[
	Shine's logging system.
]]

local Shine = Shine

local Ceil = math.ceil
local Date = os.date
local Floor = math.floor
local Notify = Shared.Message
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
	return Notify( GetTimeString()..String )
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
	if not self.Config.EnableLogging then return false end

	local String = TableConcat( LogMessages, "\n" )
	local CurrentLogFile = GetCurrentLogFile()

	--This is dumb, but append mode appears to be broken.
	local OldLog, Err = io.open( CurrentLogFile, "r" )

	local Data = ""

	if OldLog then
		Data = OldLog:read( "*all" )
		OldLog:close()
	end

	local LogFile, Err = io.open( CurrentLogFile, "w+" )

	if not LogFile then
		Shared.Message( StringFormat( "Error writing to log file: %s", Err  ) )

		return false
	end

	LogFile:write( Data, String, "\n" )
	LogFile:close()

	--Empty the logging table.
	for i = 1, #LogMessages do
		LogMessages[ i ] = nil
	end

	return true
end

--Periodically save the log file.
Shine.Hook.Add( "EndGame", "SaveLog", function()
	Shine:SaveLog()
end, Shine.Hook.MAX_PRIORITY )

Shine.Hook.Add( "MapChange", "SaveLog", function()
	Shine:SaveLog()
end, Shine.Hook.MAX_PRIORITY )

Shine.Timer.Create( "LogSave", 300, -1, function()
	Shine:SaveLog()
end )

Shine:RegisterCommand( "sh_flushlog", nil, function( Client )
	if Shine:SaveLog() then
		Shine:AdminPrint( Client, "Log flushed successfully." )
	else
		Shine:AdminPrint( Client, "Failed to flush log. Either logging is disabled, or an error occurred." )
	end
end ):Help( "Flushes Shine's current log file to disk." )

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

	if Prefix == "" and Name == "" then
		return self:NotifyColour( Player, 255, 255, 255, String, Format, ... )
	end

	if Player == "Console" then
		Shared.Message( Message )

		return
	end

	local MessageLength = Message:UTF8Length()
	if MessageLength > kMaxChatLength then
		local Iterations = Ceil( MessageLength / kMaxChatLength )

		for i = 1, Iterations do
			self:Notify( Player, Prefix, Name, Message:UTF8Sub( 1 + kMaxChatLength * ( i - 1 ),
				kMaxChatLength * i ) )
		end

		return
	end

	local MessageTable = self.BuildChatMessage( Prefix, Name, kTeamReadyRoom,
		kNeutralTeamType, Message )

	self:ApplyNetworkMessage( Player, "Shine_Chat", MessageTable, true )

	Server.AddChatToHistory( Message, Name, 0, kTeamReadyRoom, false )
end

--[[
	Sends a coloured notification to the given player(s).
]]
function Shine:NotifyColour( Player, R, G, B, String, Format, ... )
	self:NotifyDualColour( Player, 0, 0, 0, "", R, G, B, String, Format, ... )
end

--[[
	Sends a coloured notification to the given player(s), supporting a coloured prefix.
]]
function Shine:NotifyDualColour( Player, RP, GP, BP, Prefix, R, G, B, String, Format, ... )
	local Message = Format and StringFormat( String, ... ) or String

	-- Use the maximum amount of the allowed byte length.
	local MaxBytes = kMaxChatLength * 4
	if #Message > MaxBytes then
		local Chars = Message:UTF8Encode()
		local NumBytes = 0
		local StopIndex = 1

		for i = 1, #Chars do
			NumBytes = NumBytes + #Chars[ i ]
			if NumBytes > MaxBytes then
				StopIndex = i - 1
				break
			end
		end

		Message = TableConcat( Chars, "", 1, StopIndex )
	end

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

	self:ApplyNetworkMessage( Player, "Shine_ChatCol", MessageTable, true )
end

--[[
	Similar to NotifyColour, except the message is a translation key which is
	resolved client-side.
]]

function Shine:TranslatedNotifyColour( Player, R, G, B, String, Source )
	self:TranslatedNotifyDualColour( Player, 0, 0, 0, "", R, G, B, String, Source )
end

--[[
	Similar to NotifyDualColour, except the prefix and message are translation keys which
	are resolved client-side.
]]
function Shine:TranslatedNotifyDualColour( Player, RP, GP, BP, Prefix, R, G, B, String, Source )
	self:ApplyNetworkMessage( Player, "Shine_TranslatedChatCol", {
		R = R,
		G = G,
		B = B,
		Message = String,
		RP = RP,
		GP = GP,
		BP = BP,
		Prefix = Prefix,
		Source = Source or ""
	}, true )
end

--[[
	An easy error message function.
]]
function Shine:NotifyError( Player, Message, Format, ... )
	if Player == "Console" then
		Shared.Message( Format and StringFormat( Message, ... ) or Message )
		return
	end

	self:NotifyDualColour( Player, 255, 0, 0, "[Error]", 255, 255, 255, Message, Format, ... )
end

--[[
	Sends a translation key which the client will resolve to an error message.
]]
function Shine:TranslatedNotifyError( Player, Message, Source )
	if Player == "Console" then return end

	self:TranslatedNotifyDualColour( Player, 255, 0, 0, "ERROR_TAG", 255, 255, 255, Message, Source )
end

do
	local SharedTime = Shared.GetTime

	local NextNotification = {}
	function Shine:CanNotify( Client )
		if not Client then return false end

		local NextTime = NextNotification[ Client ] or 0
		local Time = SharedTime()

		if Time < NextTime then return false end

		NextNotification[ Client ] = Time + 5

		return true
	end

	Shine.Hook.Add( "ClientDisconnect", "NextNotification", function( Client )
		NextNotification[ Client ] = nil
	end )
end

function Shine:DoCommandNotify( Client, Message, Sender, ... )
	local IsConsole = not Client
	local Name

	if IsConsole then
		Name = self.Config.ConsoleName
	else
		local Player = Client:GetControllingPlayer()
		if Player then
			Name = Player:GetName()
		else
			Name = self.Config.ChatName
		end
	end

	if not self.Config.NotifyOnCommand then
		-- Console can see the success already.
		if IsConsole then return end

		-- Always notify the client that performed the action to confirm
		-- that their command was a success.
		Sender( self, Client, Name, Message, ... )

		return
	end

	local Clients = self.GameIDs
	local Immunity = self:GetUserImmunity( Client )

	local NotifyAnonymous = self.Config.NotifyAnonymous
	local NotifyAdminAnonymous = self.Config.NotifyAdminAnonymous

	for Target in Clients:Iterate() do
		--Console should always notify with its special name.
		if IsConsole then
			Sender( self, Target, Name, Message, ... )
		else
			--If admins can't see it, no one can.
			if NotifyAdminAnonymous then
				Sender( self, Target, self.Config.ChatName, Message, ... )
			else
				local TargetImmunity = self:GetUserImmunity( Target )
				local IsGreaterEqual = TargetImmunity >= Immunity

				--They're greater equal in rank, so show the name.
				if IsGreaterEqual then
					Sender( self, Target, Name, Message, ... )
				else
					--If we're set to be anonymous to lower ranks, use the set generic admin name.
					if NotifyAnonymous then
						Sender( self, Target, self.Config.ChatName, Message, ... )
					else --Otherwise use the admin's name.
						Sender( self, Target, Name, Message, ... )
					end
				end
			end
		end
	end
end

do
	local function SendNonTranslatedMessage( self, Target, Name, Message )
		self:NotifyDualColour( Target, 255, 255, 0, Name, 255, 255, 255, Message )
	end

	--[[
		Notifies players of a command, obeying the settings for who can see names,
		and how the console should be displayed.
	]]
	function Shine:CommandNotify( Client, Message, Format, ... )
		Message = Format and StringFormat( Message, ... ) or Message

		self:DoCommandNotify( Client, Message, SendNonTranslatedMessage )
	end
end

local OldServerAdminPrint = ServerAdminPrint

local MaxPrintLength = 127

Shine.Hook.Add( "OnFirstThink", "OverrideServerAdminPrint", function( Deltatime )
	local StringExplode = string.Explode
	local StringLen = string.len
	local StringSub = string.sub
	local TableInsert = table.insert

	--[[
		Rewrite ServerAdminPrint to not print to the server console when used,
		otherwise we'll get spammed with repeat prints when sending to lots of people at once.

		Also make it word-wrap overflowing text.
	]]
	function ServerAdminPrint( Client, Message, TextWrap )
		if not Client then return end

		local Len = StringLen( Message )
		if Len <= MaxPrintLength then
			Shine.SendNetworkMessage( Client, "ServerAdminPrint",
				{ message = Message }, true )
			return
		end

		local Lines = {}

		if TextWrap then
			local Parts = Ceil( Len / MaxPrintLength )
			for i = 1, Parts do
				Lines[ i ] = StringSub( Message, ( i - 1 ) * MaxPrintLength + 1, i * MaxPrintLength )
			end
		else
			local Words = StringExplode( Message, " " )
			local i = 1
			local Start = i

			while i <= #Words do
				local Text = TableConcat( Words, " ", Start, i )

				if StringLen( Text ) > MaxPrintLength then
					if i == Start then
						TableInsert( Words, i + 1, StringSub( Text, MaxPrintLength + 1 ) )
						Text = StringSub( Text, 1, MaxPrintLength )

						Start = i + 1
					else
						Text = TableConcat( Words, " ", Start, i - 1 )
						Start = i
						i = i - 1
					end

					Lines[ #Lines + 1 ] = Text
				elseif i == #Words then
					Lines[ #Lines + 1 ] = Text
				end

				i = i + 1
			end
		end

		for i = 1, #Lines do
			Shine.SendNetworkMessage( Client, "ServerAdminPrint",
				{ message = Lines[ i ] }, true )
		end
	end
end )

--[[
	Prints a translated value to the given target(s) console.
]]
function Shine:TranslatedConsolePrint( Client, MessageKey, Source )
	self:ApplyNetworkMessage( Client, "Shine_TranslatedConsoleMessage", {
		Source = Source,
		MessageKey = MessageKey
	}, true )
end

do
	local DEFAULT_DURATION = 5
	function Shine:SendNotification( Client, Type, Message, OnlyIfAdminMenuOpen, Duration )
		self:ApplyNetworkMessage( Client, "Shine_Notification", {
			Type = Type,
			Message = Message,
			Duration = Duration or DEFAULT_DURATION,
			OnlyIfAdminMenuOpen = OnlyIfAdminMenuOpen or false
		}, true )
	end

	function Shine:SendTranslatedNotification( Client, Type, MessageKey, Source, OnlyIfAdminMenuOpen, Duration )
		self:ApplyNetworkMessage( Client, "Shine_TranslatedNotification", {
			Type = Type,
			MessageKey = MessageKey,
			Source = Source or "",
			Duration = Duration or DEFAULT_DURATION,
			OnlyIfAdminMenuOpen = OnlyIfAdminMenuOpen or false
		}, true )
	end
end

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

do
	local StringRep = string.rep

	local function PrintToConsole( Client, Message )
		if not Client then
			Notify( Message )
			return
		end

		ServerAdminPrint( Client, Message )
	end

	Shine.PrintToConsole = PrintToConsole

	function Shine.PrintTableToConsole( Client, Columns, Data )
		local CharSizes = {}
		local RowData = {}
		local TotalLength = 0
		-- I really wish the console was a monospace font...
		local SpaceMultiplier = 1.5

		for i = 1, #Columns do
			local Column = Columns[ i ]

			Column.OldName = Column.OldName or Column.Name
			Column.Name = Column.OldName..StringRep( " ", 4 )

			local Name = Column.Name
			local Getter = Column.Getter

			local Rows = {}

			local Max = #Name
			for j = 1, #Data do
				local Entry = Data[ j ]

				local String = Getter( Entry )
				local StringLength = #String + 4
				if StringLength > Max then
					Max = StringLength
				end

				Rows[ j ] = String
			end

			for j = 1, #Rows do
				local Entry = Rows[ j ]
				local Diff = Max - #Entry
				if Diff > 0 then
					Rows[ j ] = Entry..StringRep( " ", Diff )
				end
			end

			TotalLength = TotalLength + Max

			local NameDiff = Max - #Name
			if NameDiff > 0 then
				Column.Name = Name..StringRep( " ", Floor( NameDiff * SpaceMultiplier ) )
			end

			RowData[ i ] = Rows
		end

		local TopRow = {}
		for i = 1, #Columns do
			TopRow[ i ] = Columns[ i ].Name
		end

		PrintToConsole( Client, TableConcat( TopRow, "" ) )
		PrintToConsole( Client, StringRep( "=", TotalLength ) )

		for i = 1, #Data do
			local Row = {}

			for j = 1, #RowData do
				Row[ j ] = RowData[ j ][ i ]
			end

			PrintToConsole( Client, TableConcat( Row, "" ) )
		end
	end
end
