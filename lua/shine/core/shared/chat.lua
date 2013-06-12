--[[
	Shine custom chat message system.
]]

Shine = Shine or {}

local StringFormat = string.format

local StringMessage = StringFormat( "string (%d)", kMaxChatLength )

local ChatMessage = {
	Prefix = "string (25)",
	Name = "string (" .. kMaxNameLength .. ")",
	TeamNumber = "integer (" .. kTeamInvalid .. " to " .. kSpectatorIndex .. ")",
	TeamType = "integer (" .. kNeutralTeamType .. " to " .. kAlienTeamType .. ")",
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
local DebugGetUpValue = debug.getupvalue

local function GetUpValue( Func, Name )
	local i = 1
	while true do
		local N, Val = DebugGetUpValue( Func, i )
		if not N then break end

		if N == Name then
			return Val
		end
		i = i + 1
	end

	return nil
end

Client.HookNetworkMessage( "Shine_Chat", function( Message )
	local ChatMessages = GetUpValue( ChatUI_GetMessages, "chatMessages" ) --This grabs the chatMessages table from lua/Chat.lua

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
			For some reason, blank messages cause it not to take up a line. i.e, sending 3 messages in a row of this form would render over each other.
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

	Shared.PlaySound( self, Player:GetChatSound() )

	if not Client.GetIsRunningServer() then
		if not Notify then
			Shared.Message( "Chat "..Message.Prefix.." - "..Message.Name..": "..Message.Message )
		else
			Shared.Message( Message.Message )
		end
	end
end )

--Displays a coloured message.
Client.HookNetworkMessage( "Shine_ChatCol", function( Message )
	local R = Message.R / 255
	local G = Message.G / 255
	local B = Message.B / 255

	local String = Message.Message

	local ChatMessages = GetUpValue( ChatUI_GetMessages, "chatMessages" )

	if not ChatMessages then
		Shared.Message( "[Shine] Unable to retrieve message table!" )
		return
	end

	local Player = Client.GetLocalPlayer()

	if not Player then return end

	ChatMessages[ #ChatMessages + 1 ] = 0xFFD800
	ChatMessages[ #ChatMessages + 1 ] = ""

	ChatMessages[ #ChatMessages + 1 ] = Color( R, G, B, 1 )
	ChatMessages[ #ChatMessages + 1 ] = String

	ChatMessages[ #ChatMessages + 1 ] = ""
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0
	ChatMessages[ #ChatMessages + 1 ] = 0

	Shared.PlaySound( self, Player:GetChatSound() )
end )
