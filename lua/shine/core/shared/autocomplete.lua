--[[
	Auto-complete service.
]]

local StringFormat = string.format

local AutoComplete = {}
Shine.AutoComplete = AutoComplete

AutoComplete.CHAT_COMMAND = 0
AutoComplete.CONSOLE_COMMAND = 1

local MaxID = 255
local MaxResponses = 10

do
	local RequestIDField = StringFormat( "integer (0 to %i)", MaxID - 1 )

	Shared.RegisterNetworkMessage( "Shine_AutoCompleteRequest", {
		SearchText = "string (32)",
		Type = "integer (0 to 1)",
		DesiredResults = "integer (1 to 10)",
		RequestID = RequestIDField
	} )

	Shared.RegisterNetworkMessage( "Shine_AutoCompleteResponse", {
		ChatCommand = "string (32)",
		ConsoleCommand = "string (32)",
		Parameters = "string (64)",
		Description = "string (128)",
		Index = StringFormat( "integer (1 to %i)", MaxResponses ),
		Total = StringFormat( "integer (1 to %i)", MaxResponses ),
		RequestID = RequestIDField
	} )

	Shared.RegisterNetworkMessage( "Shine_AutoCompleteFailed", {
		RequestID = RequestIDField
	} )
end

if Server then
	local Min = math.min

	Server.HookNetworkMessage( "Shine_AutoCompleteRequest", function( Client, Message )
		local Matches = Shine:FindCommands( Message.SearchText,
			Message.Type == AutoComplete.CHAT_COMMAND and "ChatCmd" or "ConCmd" )

		Shine.Stream( Matches ):Reduce( function( Command )
			return Shine:HasAccess( Client, Command.ConCommand )
		end )

		local NumResults = Min( #Matches, Message.DesiredResults, MaxResponses )
		if NumResults == 0 then
			Shine.SendNetworkMessage( Client, "Shine_AutoCompleteFailed", {
				RequestID = Message.RequestID
			}, true )

			return
		end

		for i = 1, NumResults do
			local Command = Matches[ i ]
			local ChatCommand = Command.MatchedIndex
				and Command.ChatCmd[ Command.MatchedIndex ] or Command.ChatCmd

			local Description = Command:GetHelp( true ) or "No help provided."
			if Command.GetAdditionalInfo then
				Description = Description..Command:GetAdditionalInfo()
			end

			Shine.SendNetworkMessage( Client, "Shine_AutoCompleteResponse", {
				ChatCommand = ChatCommand,
				ConsoleCommand = Command.ConCmd,
				Parameters = Command:GetParameterHelp(),
				Description = Description,
				Index = i,
				Total = NumResults,
				RequestID = Message.RequestID
			}, true )
		end
	end )

	return
end

local Requests = {}
local ID = 0

function AutoComplete:Request( SearchText, Type, DesiredResults, OnReceived )
	ID = ( ID + 1 ) % MaxID

	Shine.SendNetworkMessage( "Shine_AutoCompleteRequest", {
		SearchText = SearchText,
		Type = Type,
		DesiredResults = DesiredResults,
		RequestID = ID
	}, true )

	Requests[ ID ] = {
		Callback = OnReceived,
		Results = {}
	}
end

Client.HookNetworkMessage( "Shine_AutoCompleteResponse", function( Message )
	local Request = Requests[ Message.RequestID ]
	if not Request then return end

	Request.Results[ Message.Index ] = Message

	for i = 1, Message.Total do
		if not Request.Results[ i ] then
			return
		end
	end

	Request.Callback( Request.Results )
end )

Client.HookNetworkMessage( "Shine_AutoCompleteFailed", function( Message )
	local Request = Requests[ Message.RequestID ]
	if not Request then return end

	Request.Callback( Request.Results )
end )
