--[[
	Shine custom chat message system.
]]

Shine = Shine or {}

local StringFormat = string.format

local StringMessage = StringFormat( "string (%i)", kMaxChatLength )

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

local GetUpValue = Shine.GetUpValue
local IsType = Shine.IsType
local tonumber = tonumber
local tostring = tostring

local function ToHex( Dec )
	Dec = StringFormat( "%X", Dec )

	if #Dec == 1 then
		Dec = "0"..Dec
	end

	return Dec
end

local function RGBToHex( R, G, B )
	R = ToHex( R )
	G = ToHex( G )
	B = ToHex( B )

	return tonumber( StringFormat( "0x%s%s%s", R, G, B ) )
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

--[[
	Adds a message to the chat.

	Inputs:
		RP, GP, BP - Colour of the prefix.
		Prefix - Text to show before the message.
		R, G, B - Message colour.
		Message - Message text.
]]
function Shine.AddChatText( RP, GP, BP, Prefix, R, G, B, Message )
	local ChatMessages = GetUpValue( ChatUI_GetMessages, "chatMessages" )

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

	ChatMessages[ #ChatMessages + 1 ] = PreHex
	ChatMessages[ #ChatMessages + 1 ] = Prefix

	ChatMessages[ #ChatMessages + 1 ] = Color( R, G, B, 1 )
	ChatMessages[ #ChatMessages + 1 ] = Message

	ChatMessages[ #ChatMessages + 1 ] = ""
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0

	Shared.PlaySound( nil, Player:GetChatSound() )
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
	local ChatMessages = GetUpValue( ChatUI_GetMessages, "chatMessages" )

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

	--Team colour.
	ChatMessages[ #ChatMessages + 1 ] = PreHex

	--This shows just the message, no name, no prefix.
	if Prefix == "" and Name == "" then
		--[[
			For some reason, blank messages cause it not to take up a line. 
			i.e, sending 3 messages in a row of this form would render over each other.
			Hence the hacky part where I set the message to a load of spaces.
		]]
		ChatMessages[ #ChatMessages + 1 ] = String
		ChatMessages[ #ChatMessages + 1 ] = TeamCol
		ChatMessages[ #ChatMessages + 1 ] = "                     "
		Notify = true
	else
		--Prefix
		local PrefixText = StringFormat( "%s%s: ", Prefix ~= "" and "("..Prefix..") " or "", Name )
		ChatMessages[ #ChatMessages + 1 ] = PrefixText
		--Team text colour.
		ChatMessages[ #ChatMessages + 1 ] = TeamCol
		--Message
		ChatMessages[ #ChatMessages + 1 ] = String
	end

	--Useless stuff
	ChatMessages[ #ChatMessages + 1 ] = ""
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0

	Shared.PlaySound( nil, Player:GetChatSound() )

	if not Client.GetIsRunningServer() then
		if not Notify then
			Shared.Message( StringFormat( "Chat %s - %s: %s", Prefix, Name, String ) )
		else
			Shared.Message( String )
		end
	end
end )
