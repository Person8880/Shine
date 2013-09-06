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

--[[
	As UWE do not have an easy hook into the chat without copying the entire file into your mod, time for hax.
]]
local GetUpValue = Shine.GetUpValue

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

	--Team colour.
	ChatMessages[ #ChatMessages + 1 ] = GetColorForTeamNumber( Message.TeamNumber )

	if Message.Prefix == "" and Message.Name == "" then --This shows just the message, no name, no prefix.
		--[[
			For some reason, blank messages cause it not to take up a line. 
			i.e, sending 3 messages in a row of this form would render over each other.
			Hence the hacky part where I set the message to a load of spaces.
		]]
		ChatMessages[ #ChatMessages + 1 ] = Message.Message
		ChatMessages[ #ChatMessages + 1 ] = kChatTextColor[ Message.TeamType ]
		ChatMessages[ #ChatMessages + 1 ] = "                     "
		Notify = true
	else
		--Prefix
		local PrefixText = StringFormat( "%s%s: ", Message.Prefix ~= "" and "("..Message.Prefix..") " or "", Message.Name )
		ChatMessages[ #ChatMessages + 1 ] = PrefixText
		--Team text colour.
		ChatMessages[ #ChatMessages + 1 ] = kChatTextColor[ Message.TeamType ]
		--Message
		ChatMessages[ #ChatMessages + 1 ] = Message.Message
	end

	--Useless stuff
	ChatMessages[ #ChatMessages + 1 ] = ""
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0

	Shared.PlaySound( nil, Player:GetChatSound() )

	if not Client.GetIsRunningServer() then
		if not Notify then
			Shared.Message( "Chat "..Message.Prefix.." - "..Message.Name..": "..Message.Message )
		else
			Shared.Message( Message.Message )
		end
	end
end )
