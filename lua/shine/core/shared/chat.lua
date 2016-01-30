--[[
	Shine custom chat message system.
]]

local StringFormat = string.format

do
	local StringMessage = StringFormat( "string (%i)", kMaxChatLength * 4 + 1 )

	local ChatMessage = {
		Prefix = "string (25)",
		Name = StringFormat( "string (%i)", kMaxNameLength ),
		TeamNumber = StringFormat( "integer (%i to %i)", kTeamInvalid, kSpectatorIndex ),
		TeamType = StringFormat( "integer (%i to %i)", kNeutralTeamType, kAlienTeamType ),
		Message = StringMessage
	}

	function Shine.BuildChatMessage( Prefix, Name, TeamNumber, TeamType, Message )
		return {
			Prefix = Prefix,
			Name = Name,
			TeamNumber = TeamNumber,
			TeamType = TeamType,
			Message = Message
		}
	end

	Shared.RegisterNetworkMessage( "Shine_Chat", ChatMessage )
	Shared.RegisterNetworkMessage( "Shine_ChatCol", {
		RP = "integer (0 to 255)",
		GP = "integer (0 to 255)",
		BP = "integer (0 to 255)",
		Prefix = StringMessage,
		R = "integer (0 to 255)",
		G = "integer (0 to 255)",
		B = "integer (0 to 255)",
		Message = StringMessage
	} )
	Shared.RegisterNetworkMessage( "Shine_TranslatedChatCol", {
		RP = "integer (0 to 255)",
		GP = "integer (0 to 255)",
		BP = "integer (0 to 255)",
		Prefix = StringMessage,
		R = "integer (0 to 255)",
		G = "integer (0 to 255)",
		B = "integer (0 to 255)",
		Message = StringMessage,
		Source = "string (20)"
	} )
	Shared.RegisterNetworkMessage( "Shine_TranslatedConsoleMessage", {
		Source = "string (20)",
		MessageKey = "string (32)"
	} )
end

if Server then return end

Client.HookNetworkMessage( "Shine_TranslatedConsoleMessage", function( Data )
	local Source = Data.Source
	if Source == "" then
		Source = "Core"
	end

	Shared.Message( Shine.Locale:GetPhrase( Source, Data.MessageKey ) )
end )

local BitLShift = bit.lshift
local IsType = Shine.IsType
local tostring = tostring

local function RGBToHex( R, G, B )
	return BitLShift( R, 16 ) + BitLShift( G, 8 ) + B
end

local function AddChatMessage( Player, ChatMessages, PreHex, Prefix, Col, Message )
	ChatMessages[ #ChatMessages + 1 ] = PreHex
	ChatMessages[ #ChatMessages + 1 ] = Prefix

	ChatMessages[ #ChatMessages + 1 ] = Col
	ChatMessages[ #ChatMessages + 1 ] = Message

	ChatMessages[ #ChatMessages + 1 ] = false
	ChatMessages[ #ChatMessages + 1 ] = false

	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0

	StartSoundEffect( Player:GetChatSound() )
end

local GUIChatMessages
local function GetChatMessages()
	return GUIChatMessages
end

local function SetupChatMessages()
	if not GetChatMessages() then
		Shine.JoinUpValues( ChatUI_GetMessages, GetChatMessages, {
			chatMessages = "GUIChatMessages"
		} )
	end
end

local function SetupAndGetChatMessages()
	SetupChatMessages()

	local ChatMessages = GetChatMessages()
	if not ChatMessages then
		Shared.Message( "[Shine] Unable to retrieve message table!" )
		return nil
	end

	return ChatMessages
end

--[[
	Adds a message to the chat.

	Inputs:
		RP, GP, BP - Colour of the prefix.
		Prefix - Text to show before the message.
		R, G, B - Message colour.
		Message - Message text.
]]
function Shine.AddChatText( RP, GP, BP, Prefix, R, G, B, Message )
	local ChatMessages = SetupAndGetChatMessages()
	if not ChatMessages then return end

	local Player = Client.GetLocalPlayer()
	if not Player then return end

	AddChatMessage( Player, ChatMessages, RGBToHex( RP, GP, BP ),
		Prefix, Color( R, G, B, 1 ), Message )
end

--[[
	Client-side version of notify error, displays the translated error tag and the passed in message.
]]
function Shine:NotifyError( Message )
	self.AddChatText( 255, 0, 0, self.Locale:GetPhrase( "Core", "ERROR_TAG" ), 1, 1, 1, Message )
end

--Displays a coloured message.
Client.HookNetworkMessage( "Shine_ChatCol", function( Message )
	local R = Message.R / 255
	local G = Message.G / 255
	local B = Message.B / 255

	local String = Message.Message
	local Prefix = Message.Prefix

	Shine.AddChatText( Message.RP, Message.GP, Message.BP, Prefix, R, G, B, String )
end )

Client.HookNetworkMessage( "Shine_TranslatedChatCol", function( Message )
	local R = Message.R / 255
	local G = Message.G / 255
	local B = Message.B / 255

	local Source = Message.Source
	if Source == "" then
		Source = "Core"
	end

	local String = Shine.Locale:GetPhrase( Source, Message.Message )
	local Prefix = Shine.Locale:GetPhrase( Source, Message.Prefix )
	-- Fall back to core strings for prefix if not found.
	if Prefix == Message.Prefix and Source ~= "Core" then
		Prefix = Shine.Locale:GetPhrase( "Core", Message.Prefix )
	end

	Shine.AddChatText( Message.RP, Message.GP, Message.BP, Prefix, R, G, B, String )
end )

--Deprecated chat message. Only useful for PMs/Admin say messages.
Client.HookNetworkMessage( "Shine_Chat", function( Message )
	local ChatMessages = SetupAndGetChatMessages()
	if not ChatMessages then return end

	local Player = Client.GetLocalPlayer()
	if not Player then return end

	local Notify
	local PreHex = GetColorForTeamNumber( Message.TeamNumber )
	local Prefix = Message.Prefix
	local Name = Message.Name
	local String = Message.Message
	local TeamCol = kChatTextColor[ Message.TeamType ] or Color( 1, 1, 1, 1 )

	--This shows just the message, no name, no prefix (no longer used as it doesn't work).
	if Prefix == "" and Name == "" then
		Prefix = String
		String = "                     "

		Notify = true
	else
		Prefix = StringFormat( "%s%s: ", Prefix ~= "" and "("..Prefix..") " or "", Name )
	end

	AddChatMessage( Player, ChatMessages, PreHex, Prefix, TeamCol, String )

	if not Client.GetIsRunningServer() then
		if not Notify then
			Shared.Message( StringFormat( "Chat %s - %s: %s", Prefix, Name, String ) )
		else
			Shared.Message( String )
		end
	end
end )
