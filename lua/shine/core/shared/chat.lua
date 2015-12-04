--[[
	Shine custom chat message system.
]]

local StringFormat = string.format

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

local ColourMessage = {
	RP = "integer (0 to 255)",
	GP = "integer (0 to 255)",
	BP = "integer (0 to 255)",
	Prefix = StringMessage,
	R = "integer (0 to 255)",
	G = "integer (0 to 255)",
	B = "integer (0 to 255)",
	Message = StringMessage
}

Shared.RegisterNetworkMessage( "Shine_ChatCol", ColourMessage )

if Server then return end

local IsType = Shine.IsType
local tonumber = tonumber
local tostring = tostring

local function RGBToHex( R, G, B )
	return tonumber( StringFormat( "0x%.2X%.2X%.2X", R, G, B ) )
end

--Oh boy this is awful, but I'd rather catch the error than have pretty code.
local function CheckArgs( RP, GP, BP, PreHex, Prefix, R, G, B, Message )
	if not IsType( PreHex, "number" ) or not IsType( Prefix, "string" )
	or not IsType( R, "number" ) or not IsType( G, "number" )
	or not IsType( B, "number" ) or not IsType( Message, "string" ) then
		Shine:AddErrorReport( "Shine.AddChatText did not receive correct values.",
			"RGBP: %s %s %s. PreHex: %s. Prefix: '%s'. Message: '%s'. RGB: %s %s %s", true,
			tostring( RP ), tostring( GP ), tostring( BP ),
			tostring( PreHex ), tostring( Prefix ), tostring( Message ),
			tostring( R ), tostring( G ), tostring( B ) )

		return false
	end

	return true
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

local ChatMessages
local function GetChatMessages()
	return ChatMessages
end

local function SetupChatMessages()
	if not ChatMessages then
		Shine.JoinUpValues( ChatUI_GetMessages, GetChatMessages, {
			chatMessages = "ChatMessages"
		} )
	end
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
	SetupChatMessages()

	local ChatMessages = GetChatMessages()
	if not ChatMessages then
		Shared.Message( "[Shine] Unable to retrieve message table!" )

		return
	end

	local Player = Client.GetLocalPlayer()
	if not Player then return end

	local PreHex = RGBToHex( RP, GP, BP )

	if not CheckArgs( RP, GP, BP, PreHex, Prefix, R, G, B, Message ) then
		return
	end

	AddChatMessage( Player, ChatMessages, PreHex, Prefix, Color( R, G, B, 1 ), Message )
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

--Deprecated chat message. Only useful for PMs/Admin say messages.
Client.HookNetworkMessage( "Shine_Chat", function( Message )
	SetupChatMessages()

	local ChatMessages = GetChatMessages()

	if not ChatMessages then
		Shared.Message( "[Shine] Unable to retrieve message table!" )
		return
	end

	local Player = Client.GetLocalPlayer()
	if not Player then return end

	local Notify
	local PreHex = GetColorForTeamNumber( Message.TeamNumber )
	local Prefix = Message.Prefix
	local Name = Message.Name
	local String = Message.Message
	local TeamCol = kChatTextColor[ Message.TeamType ] or Color( 1, 1, 1, 1 )

	if not CheckArgs( nil, nil, nil, PreHex, Prefix, TeamCol.r, TeamCol.g, TeamCol.b, String ) then
		return
	end

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
