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

	Shared.RegisterNetworkMessage( "Shine_AutoCompleteParametersRequest", {
		SearchText = "string (32)",
		Type = "integer (0 to 1)",
		Command = "string (32)",
		ParameterIndex = "integer (1 to 31)",
		DesiredResults = "integer (1 to 10)",
		RequestID = RequestIDField
	} )

	Shared.RegisterNetworkMessage( "Shine_AutoCompleteResponse", {
		ChatCommand = "string (32)",
		ConsoleCommand = "string (32)",
		Parameters = "string (96)",
		Description = "string (128)",
		Index = StringFormat( "integer (1 to %i)", MaxResponses ),
		Total = StringFormat( "integer (1 to %i)", MaxResponses ),
		RequestID = RequestIDField
	} )

	Shared.RegisterNetworkMessage( "Shine_AutoCompleteParametersResponse", {
		ChatCommand = "string (32)",
		ConsoleCommand = "string (32)",
		Parameter = "string (96)",
		Parameters = "string (96)",
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
	local IsType = Shine.IsType
	local Min = math.min
	local StringFind = string.find
	local StringLower = string.lower
	local TableSort = table.sort

	local function FailAutoCompleteRequest( Client, Message )
		Shine.SendNetworkMessage( Client, "Shine_AutoCompleteFailed", {
			RequestID = Message.RequestID
		}, true )
	end

	local function GetCommandDescription( Command )
		local Description = Command:GetHelp( true ) or "No help provided."
		if Command.GetAdditionalInfo then
			Description = Description..Command:GetAdditionalInfo()
		end
		return Description
	end

	Shine.HookNetworkMessage( "Shine_AutoCompleteRequest", function( Client, Message )
		local Matches = Shine:FindCommands( Message.SearchText,
			Message.Type == AutoComplete.CHAT_COMMAND and "ChatCmd" or "ConCmd" )

		Shine.Stream( Matches ):Filter( function( Result )
			return Shine:GetPermission( Client, Result.Command.ConCmd )
		end )

		local NumResults = Min( #Matches, Message.DesiredResults, MaxResponses )
		if NumResults == 0 then
			FailAutoCompleteRequest( Client, Message )
			return
		end

		local IsConsoleCommandSearch = Message.Type == AutoComplete.CONSOLE_COMMAND

		for i = 1, NumResults do
			local Result = Matches[ i ]
			local Command = Result.Command
			local ChatCommand = Result.MatchedIndex
				and Command.ChatCmd[ Result.MatchedIndex ] or Command.ChatCmd
			if IsConsoleCommandSearch and IsType( ChatCommand, "table" ) then
				ChatCommand = ChatCommand[ 1 ]
			end

			local Description = GetCommandDescription( Command )

			Shine.SendNetworkMessage( Client, "Shine_AutoCompleteResponse", {
				ChatCommand = ChatCommand or "",
				ConsoleCommand = Command.ConCmd,
				Parameters = Command:GetParameterHelp(),
				Description = Description,
				Index = i,
				Total = NumResults,
				RequestID = Message.RequestID
			}, true )
		end
	end )

	local function SortByStartIndex( A, B )
		if A.StartIndex < B.StartIndex then
			return true
		elseif A.StartIndex > B.StartIndex then
			return false
		else
			return A.Value < B.Value
		end
	end

	Shine.HookNetworkMessage( "Shine_AutoCompleteParametersRequest", function( Client, Message )
		local Command
		if Message.Type == AutoComplete.CONSOLE_COMMAND then
			Command = Shine:GetCommand( Message.Command )
		else
			Command = Shine:GetCommandByChatCommand( Message.Command )
		end

		if not Command then
			FailAutoCompleteRequest( Client, Message )
			return
		end

		local ChatCommand = Command.ChatCmd
		if Message.Type == AutoComplete.CHAT_COMMAND then
			ChatCommand = Message.Command
		elseif IsType( ChatCommand, "table" ) then
			ChatCommand = Command.ChatCmd[ 1 ]
		end

		local Parameters = Command:GetParameterHelp()
		local Description = GetCommandDescription( Command )

		local AutoCompletions = Command:GetParameterAutoCompletions( Message.ParameterIndex )
		local Results
		if AutoCompletions then
			Results = {}

			local SearchText = StringLower( Message.SearchText )
			for i = 1, #AutoCompletions do
				local Completion = AutoCompletions[ i ]
				local StartIndex = StringFind( StringLower( Completion ), SearchText, 1, true )
				if StartIndex then
					Results[ #Results + 1 ] = {
						Value = Completion,
						StartIndex = StartIndex
					}
				end
			end
		end

		local NumResults = Results and Min( #Results, Message.DesiredResults, MaxResponses )
		if not NumResults or NumResults == 0 then
			Shine.SendNetworkMessage( Client, "Shine_AutoCompleteParametersResponse", {
				ChatCommand = ChatCommand or "",
				ConsoleCommand = Command.ConCmd,
				Parameter = "",
				Parameters = Parameters,
				Description = Description,
				Index = 1,
				Total = 1,
				RequestID = Message.RequestID
			}, true )
			return
		end

		TableSort( Results, SortByStartIndex )

		for i = 1, NumResults do
			Shine.SendNetworkMessage( Client, "Shine_AutoCompleteParametersResponse", {
				ChatCommand = ChatCommand or "",
				ConsoleCommand = Command.ConCmd,
				Parameter = Results[ i ].Value,
				Parameters = Parameters,
				Description = Description,
				Index = i,
				Total = NumResults,
				RequestID = Message.RequestID
			}, true )
		end
	end )

	return
end

local xpcall = xpcall

local ErrorHandler = Shine.BuildErrorHandler( "Auto completion request callback error" )

local Requests = {}
local ID = 0
local function CycleID()
	ID = ( ID + 1 ) % MaxID
end

function AutoComplete.Request( SearchText, Type, DesiredResults, OnReceived )
	CycleID()

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

function AutoComplete.RequestParameter( Command, Index, SearchText, Type, DesiredResults, OnReceived )
	CycleID()

	Shine.SendNetworkMessage( "Shine_AutoCompleteParametersRequest", {
		SearchText = SearchText,
		Command = Command,
		ParameterIndex = Index,
		Type = Type,
		DesiredResults = DesiredResults,
		RequestID = ID
	}, true )

	Requests[ ID ] = {
		Callback = OnReceived,
		Results = {
			Command = Command,
			ParameterIndex = Index
		}
	}
end

local function ReceiveResult( Message )
	local Request = Requests[ Message.RequestID ]
	if not Request then return end

	Request.Results[ Message.Index ] = Message

	for i = 1, Message.Total do
		if not Request.Results[ i ] then
			return
		end
	end

	xpcall( Request.Callback, ErrorHandler, Request.Results )
	Requests[ Message.RequestID ] = nil
end

Shine.HookNetworkMessage( "Shine_AutoCompleteResponse", ReceiveResult )
Shine.HookNetworkMessage( "Shine_AutoCompleteParametersResponse", ReceiveResult )

Shine.HookNetworkMessage( "Shine_AutoCompleteFailed", function( Message )
	local Request = Requests[ Message.RequestID ]
	if not Request then return end

	xpcall( Request.Callback, ErrorHandler, Request.Results )
	Requests[ Message.RequestID ] = nil
end )
