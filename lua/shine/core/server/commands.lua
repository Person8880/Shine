--[[
	Shine console/chat command handling.
]]

local IsType = Shine.IsType
local MathClamp = math.ClampEx
local Min = math.min
local pairs = pairs
local Round = math.Round
local StringExplode = string.Explode
local StringFind = string.find
local StringFormat = string.format
local StringGSub = string.gsub
local StringStartsWith = string.StartsWith
local StringSub = string.sub
local TableConcat = table.concat
local TableInsert = table.insert
local TableRemove = table.remove
local TableSort = table.sort
local tostring = tostring
local type = type
local xpcall = xpcall

local ParamTypes = Shine.CommandUtil.ParamTypes

--[[
	Command object.
	Stores the console command, chat command and the function to run when these commands are used.
]]
local CommandMeta = {}
CommandMeta.__index = CommandMeta

--[[
	Adds a parameter to a command. This defines what an argument should be parsed into.
	For instance, a paramter of type "client" will be parsed into a client
	from their name or Steam ID.
]]
function CommandMeta:AddParam( Table )
	Shine.Assert( type( Table ) == "table", "Bad argument #1 to AddParam, table expected, got %s",
		type( Table ) )

	local Args = self.Arguments
	Args[ #Args + 1 ] = Table

	return self
end

function CommandMeta:Help( HelpString )
	Shine.Assert( type( HelpString ) == "string",
		"Bad argument #1 to Help, string expected, got %s", type( HelpString ) )

	self.HelpString = HelpString

	return self
end

do
	local function GetParamHelp( ParamType, Arg )
		if IsType( ParamType.Help, "string" ) then
			return ParamType.Help
		end

		return ParamType.Help( Arg )
	end

	local function GetArgHelp( Arg, Type )
		if Arg.Help then return Arg.Help end

		if IsType( Type, "string" ) then
			return GetParamHelp( ParamTypes[ Type ], Arg )
		end

		local ParamHelpText = {}

		for i = 1, #Type do
			ParamHelpText[ i ] = GetParamHelp( ParamTypes[ Type[ i ] ], Arg )
		end

		return TableConcat( ParamHelpText, " or " )
	end

	local function GetArgDefaultMessage( Arg, Type )
		if IsType( Arg.Default, "function" ) then
			return ""
		end

		local ParamType = IsType( Type, "string" ) and ParamTypes[ Type ] or ParamTypes[ Type[ 1 ] ]

		local Default = Arg.Default
		if Default == nil then
			Default = ParamType.Default
		end

		if Default ~= nil then
			return StringFormat( " [default: '%s']", Default )
		end

		return ""
	end

	function CommandMeta:GetParameterHelp()
		local Args = self.Arguments
		if #Args == 0 then
			return ""
		end

		local Message = {}

		for i = 1, #Args do
			local Arg = Args[ i ]
			local Type = Arg.Type

			local ParamType = ParamTypes[ Arg.Type ]
			Message[ i ] = StringFormat( Arg.Optional and "(%s%s)" or "<%s>",
				GetArgHelp( Arg, Type ),
				GetArgDefaultMessage( Arg, Type ) )
		end

		return TableConcat( Message, " " )
	end

	function CommandMeta:GetHelp( OnlyHelpString )
		local Args = self.Arguments

		-- Legacy help message.
		if OnlyHelpString or #Args == 0 or StringStartsWith( self.HelpString, "<" ) then
			return self.HelpString
		end

		return StringFormat( "%s %s", self:GetParameterHelp(), self.HelpString )
	end
end

--[[
	Creates a command object.
	The object stores the console command, chat command, function to run,
	permission setting and silent setting.
	It can also have parameters added to it to pass to its function.
]]
local function Command( ConCommand, ChatCommand, Function, NoPermissions, Silent )
	return setmetatable( {
		ConCmd = ConCommand,
		ChatCmd = ChatCommand,
		Func = Function,
		NoPerm = NoPermissions,
		Silent = Silent,
		Arguments = {}
	}, CommandMeta )
end

Shine.Commands = {}
Shine.ChatCommands = {}

local HookedCommands = {}

--[[
	Registers a Shine command.
	Inputs:
		1. Console command to assign.
		2. Optional chat command(s) to assign.
		3. Function to run.
		4. Optional flag to allow anyone to run the command.
		5. Optional flag to always be silent.
	Output: Command object.
]]
function Shine:RegisterCommand( ConCommand, ChatCommand, Function, NoPerm, Silent )
	self.Assert( type( ConCommand ) == "string",
		"Bad argument #1 to RegisterCommand, string expected, got %s", type( ConCommand ) )

	if ChatCommand then
		self.Assert( type( ChatCommand ) == "string" or type( ChatCommand ) == "table",
			"Bad argument #2 to RegisterCommand, string or table expected, got %s",
			type( ChatCommand ) )
	end

	self.Assert( type( Function ) == "function",
		"Bad argument #3 to RegisterCommand, function expected, got %s", type( Function ) )

	local Commands = self.Commands

	local CmdObj = Command( ConCommand, ChatCommand, Function, NoPerm, Silent )

	Commands[ ConCommand ] = CmdObj

	if ChatCommand then
		local ChatCommands = self.ChatCommands

		--Adding a table of chat commands so a console command can be tied to more than one.
		if type( ChatCommand ) == "table" then
			for i = 1, #ChatCommand do
				ChatCommands[ ChatCommand[ i ] ] = CmdObj
			end
		else
			ChatCommands[ ChatCommand ] = CmdObj
		end
	end

	--This prevents hooking again if a plugin is reloaded.
	if not HookedCommands[ ConCommand ] then
		Event.Hook( "Console_"..ConCommand, function( Client, ... )
			return Shine:RunCommand( Client, ConCommand, false, ... )
		end )
		HookedCommands[ ConCommand ] = true
	end

	return CmdObj
end

function Shine:FindCommands( SearchText, Field )
	local Results = {}

	for ConCommand, Command in pairs( self.Commands ) do
		if not Command.Disabled and Command[ Field ] then
			local Value = Command[ Field ]
			local Start
			local MatchedIndex

			if IsType( Value, "string" ) then
				Start = Value == SearchText and 0 or StringFind( Value, SearchText, 1, true )
			else
				for i = 1, #Value do
					local CurStart = Value[ i ] == SearchText and 0 or StringFind( Value[ i ], SearchText, 1, true )

					if CurStart then
						if not Start then
							Start = CurStart
							MatchedIndex = i
						elseif CurStart < Start then
							MatchedIndex = i
							Start = CurStart
						end
					end
				end
			end

			if Start then
				Results[ #Results + 1 ] = { Start = Start, Command = Command, MatchedIndex = MatchedIndex }
			end
		end
	end

	return Shine.Stream( Results ):Sort( function( A, B )
		return A.Start < B.Start
	end ):AsTable()
end

--[[
	Removes a registered Shine command.
	Inputs: Console command, optional chat command.

	Note that we do not remove the command from 'HookedCommands',
	as NS2's hook system lacks a way to remove hooks.
]]
function Shine:RemoveCommand( ConCommand, ChatCommand )
	self.Commands[ ConCommand ] = nil
	if ChatCommand then
		if type( ChatCommand ) == "table" then
			for i = 1, #ChatCommand do
				self.ChatCommands[ ChatCommand[ i ] ] = nil
			end
		else
			self.ChatCommands[ ChatCommand ] = nil
		end
	end
end

local IsType = Shine.IsType

--These define what to return for the given command arguments.
local TargetFuncs = {
	[ "@spectate" ] = function() return Shine.GetTeamClients( 3 ) end,
	[ "@readyroom" ] = function() return Shine.GetTeamClients( kTeamReadyRoom ) end,
	[ "@marine" ] = function() return Shine.GetTeamClients( 1 ) end,
	[ "@alien" ] = function() return Shine.GetTeamClients( 2 ) end,
	[ "@blue" ] = function() return Shine.GetTeamClients( 1 ) end,
	[ "@orange" ] = function() return Shine.GetTeamClients( 2 ) end,
	[ "@gold" ] = function() return Shine.GetTeamClients( 2 ) end
}

local GetDefault = Shine.CommandUtil.GetDefaultValue

--Client looks for a matching client by game ID, Steam ID and name. Returns 1 client.
ParamTypes.client = {
	Parse = function( Client, String, Table )
		if not String then
			return GetDefault( Table ) or Client
		end

		local Target
		if String == "^" then
			Target = Client
		elseif String:sub( 1, 1 ) == "$" then
			local ID = String:sub( 2 )
			local ToNum = tonumber( ID )

			if ToNum then
				Target = Shine.GetClientByNS2ID( ToNum )
			else
				Target = Shine:GetClientBySteamID( ID )
			end
		else
			Target = Shine:GetClient( String )
		end

		if Table.NotSelf and Target == Client then
			return nil, true
		end

		return Target
	end,
	Help = "player",
	OnFailedMatch = function( Client, Arg, SelfTargeting )
		if SelfTargeting then
			Shine:NotifyCommandError( Client, "You cannot target yourself with this command." )
		else
			Shine:NotifyCommandError( Client, "No matching player was found." )
		end
	end,
	Validate = function( Client, Arg, ParsedArg )
		if not ParsedArg then return true end
		if Arg.IgnoreCanTarget then return true end

		if not Shine:CanTarget( Client, ParsedArg ) then
			Shine:NotifyCommandError( Client, "You do not have permission to target %s.",
				true, ParsedArg:GetControllingPlayer():GetName() )

			return false
		end

		return true
	end,
	Default = "^"
}
--Clients looks for matching clients by game ID, Steam ID, name
--or special targeting directive. Returns a table of clients.
ParamTypes.clients = {
	Parse = function( Client, String, Table )
		if not String then
			return GetDefault( Table )
		end

		local Vals = StringExplode( String, "," )

		local Clients = {}
		local Targets = {}

		local AllClients = Shine.GetAllClients()
		local NumClients = #AllClients

		for i = 1, #Vals do
			local CurrentTargets = {}

			local Val = Vals[ i ]
			local Negate

			local ControlChar = Val:sub( 1, 1 )

			if ControlChar == "!" then
				Val = Val:sub( 2 )
				Negate = true
			end

			--Targeting a user group.
			if ControlChar == "%" then
				local Group = Val:sub( 2 )
				local InGroup = Shine:GetClientsByGroup( Group )

				if #InGroup > 0 then
					for j = 1, #InGroup do
						local CurClient = InGroup[ j ]

						if not CurrentTargets[ CurClient ] then
							CurrentTargets[ CurClient ] = true
						end
					end
				end
			elseif ControlChar == "$" then --Targetting a specific Steam ID.
				local ID = Val:sub( 2 )
				local ToNum = tonumber( ID )

				local CurClient

				if ToNum then
					CurClient = Shine.GetClientByNS2ID( ToNum )
				else
					CurClient = Shine:GetClientBySteamID( ID )
				end

				if CurClient and not CurrentTargets[ CurClient ] then
					CurrentTargets[ CurClient ] = true
				end
			else
				if Val == "*" then --Targeting everyone.
					for j = 1, NumClients do
						local CurClient = AllClients[ j ]

						if CurClient and not CurrentTargets[ CurClient ] then
							CurrentTargets[ CurClient ] = true
						end
					end
				elseif Val == "^" then --Targeting yourself.
					local CurClient = Client

					if not Table.NotSelf then
						if not CurrentTargets[ CurClient ] then
							CurrentTargets[ CurClient ] = true
						end
					end
				else
					if TargetFuncs[ Val ] then --Allows for targetting multiple @types at once.
						local Add = TargetFuncs[ Val ]()

						for j = 1, #Add do
							local Adding = Add[ j ]

							if not CurrentTargets[ Adding ] then
								CurrentTargets[ Adding ] = true
							end
						end
					else
						local CurClient = Shine:GetClient( Val )

						if CurClient and not ( Table.NotSelf and CurClient == Client ) then
							if not CurrentTargets[ CurClient ] then
								CurrentTargets[ CurClient ] = true
							end
						end
					end
				end
			end

			if Negate then
				if not next( Targets ) then
					for j = 1, NumClients do
						local CurClient = AllClients[ j ]

						if not CurrentTargets[ CurClient ] then
							Targets[ CurClient ] = true
						end
					end
				else
					for CurClient, Bool in pairs( CurrentTargets ) do
						Targets[ CurClient ] = nil
					end
				end
			else
				for CurClient, Bool in pairs( CurrentTargets ) do
					Targets[ CurClient ] = true
				end
			end
		end

		if Table.NotSelf and Targets[ Client ] then
			Targets[ Client ] = nil
		end

		for CurClient, Bool in pairs( Targets ) do
			Clients[ #Clients + 1 ] = CurClient
		end

		return Clients
	end,
	Help = "players",
	OnFailedMatch = function( Client, Arg )
		Shine:NotifyCommandError( Client, "No matching players were found." )
	end,
	Validate = function( Client, Arg, ParsedArg )
		if not ParsedArg then return true end
		if #ParsedArg == 0 then
			Shine:NotifyCommandError( Client, "No matching players found." )

			return false
		end

		if Arg.IgnoreCanTarget then return true end

		Shine.Stream( ParsedArg ):Reduce( function( Value )
			return Shine:CanTarget( Client, Value )
		end )

		if #ParsedArg == 0 then
			Shine:NotifyCommandError( Client,
				"You do not have permission to target anyone you specified." )

			return false
		end

		return true
	end
}
--Team takes either 0 - 3 directly or takes a string matching a team name
--and turns it into the team number.
ParamTypes.team = {
	Parse = function( Client, String, Table )
		if not String then
			return GetDefault( Table )
		end

		local ToNum = tonumber( String )

		if ToNum then return MathClamp( Round( ToNum ), 0, 3 ) end

		String = String:lower()

		if String:find( "ready" ) then return 0 end
		if String:find( "marine" ) then return 1 end
		if String:find( "blu" ) then return 1 end
		if String:find( "alien" ) then return 2 end
		if String:find( "orang" ) then return 2 end
		if String:find( "gold" ) then return 2 end
		if String:find( "spectat" ) then return 3 end

		return nil
	end,
	Help = "team"
}
ParamTypes.steamid = {
	Parse = function( Client, String, Table )
		local Num = tonumber( String )
		if Num then return Num end

		return Shine.SteamIDToNS2( String )
	end,
	Validate = function( Client, Arg, ParsedArg )
		if not ParsedArg then return true end
		if Arg.IgnoreCanTarget then return true end

		if not Shine:CanTarget( Client, ParsedArg ) then
			Shine:NotifyCommandError( Client, "You do not have permission to target %s.",
				true, ParsedArg )

			return false
		end

		return true
	end,
	Help = "steamid"
}

local ParseParameter = Shine.CommandUtil.ParseParameter

local Traceback = debug.traceback

local function OnError( Err )
	local Trace = Traceback()

	Shine:DebugPrint( "Error: %s.\n%s", true, Err, Trace )
	Shine:AddErrorReport( StringFormat( "Command error: %s.", Err ), Trace )
end

local function MatchStringRestriction( ParsedArg, Restriction )
	if not StringFind( Restriction, "*" ) then
		return ParsedArg == Restriction
	end

	Restriction = StringGSub( Restriction, "*", "(.-)" ).."$"

	return StringFind( ParsedArg, Restriction ) ~= nil
end

local ArgValidators = {
	string = function( Client, ParsedArg, ArgRestrictor )
		if IsType( ArgRestrictor, "table" ) then
			--Has to be present in the allowed list.
			for i = 1, #ArgRestrictor do
				if MatchStringRestriction( ParsedArg, ArgRestrictor[ i ] ) then
					return ParsedArg
				end
			end

			return nil
		else --Assume string, must match.
			return MatchStringRestriction( ParsedArg, ArgRestrictor ) and ParsedArg or nil
		end
	end,

	number = function( Client, ParsedArg, ArgRestrictor )
		--Invalid restrictor, should be a table with min and/or max values.
		if not IsType( ArgRestrictor, "table" ) then return ParsedArg end

		--Strict means block the command rather than clamping it into range.
		if ArgRestrictor.Strict then
			local Clamped = MathClamp( ParsedArg, ArgRestrictor.Min, ArgRestrictor.Max )
			if Clamped ~= ParsedArg then
				return nil
			end

			return ParsedArg
		end

		--Clamp the argument in range.
		return MathClamp( ParsedArg, ArgRestrictor.Min, ArgRestrictor.Max )
	end
}
ArgValidators.time = ArgValidators.number

function Shine:NotifyCommandError( Client, Message, Format, ... )
	Message = Format and StringFormat( Message, ... ) or Message

	if not Client then
		Print( Message )
		return
	end

	local FromChat = self:IsCommandFromChat()
	if FromChat then
		self:NotifyError( Client, Message )

		return
	end

	ServerAdminPrint( Client, Message )
end

local function Notify( Client, FromChat, Message, Format, ... )
	Message = Format and StringFormat( Message, ... ) or Message

	if not Client then
		Print( Message )
		return
	end

	if FromChat then
		Shine:NotifyColour( Client, 255, 160, 0, Message )

		return
	end

	ServerAdminPrint( Client, Message )
end

Shine.CommandStack = {}

--Store a stack of calling commands, which tells us if it's from the chat or not.
--This is purely in case someone uses Shine:RunCommand() during a command (which you really shouldn't).
function Shine:IsCommandFromChat()
	return self.CommandStack[ #self.CommandStack ] == true
end

local function PopCommandStack( self )
	self.CommandStack[ #self.CommandStack ] = nil
end

function Shine.CommandUtil:OnFailedMatch( Client, ConCommand, ArgString, CurArg, i )
	Shine:NotifyCommandError( Client,
		CurArg.Error or "Incorrect argument #%i to %s, expected %s.",
		true, i, ConCommand, CurArg.Type )
end

function Shine.CommandUtil:Validate( Client, ConCommand, Result, CurArg, i )
	local RestrictionIndex = tostring( i )

	if ArgRestrictions and ArgRestrictions[ RestrictionIndex ] then
		local Func = ArgValidators[ MatchedType ]

		--Apply restrictions.
		if Func then
			Result = Func( Client, Result, ArgRestrictions[ RestrictionIndex ] )

			--The restriction wiped the argument as it's not allowed.
			if Result == nil then
				Shine:NotifyCommandError( Client,
					"Invalid argument #%i, restricted in rank settings.", true, i )

				return nil
			end
		end
	end

	return Result
end

function Shine.CommandUtil:GetCommandArgs( Client, ConCommand, FromChat, Command, Args )
	local Allowed, ArgRestrictions = Shine:GetPermission( Client, ConCommand )
	if not Allowed then
		Shine:NotifyCommandError( Client, "You do not have permission to use %s.", true, ConCommand )

		return
	end

	local ExpectedArgs = Command.Arguments
	local ExpectedCount = #ExpectedArgs

	if Args[ 1 ] == nil and ExpectedCount > 0 and not ExpectedArgs[ 1 ].Optional then
		Notify( Client, FromChat, "%s - %s%s", true, ConCommand, Command:GetHelp() or "No help available.",
			Command.GetAdditionalInfo and Command:GetAdditionalInfo() or "" )

		return
	end

	local ParsedArgs = {}

	for i = 1, ExpectedCount do
		local CurArg = ExpectedArgs[ i ]
		local ArgString = Args[ i ]
		local TakeRestOfLine = CurArg.TakeRestOfLine

		if TakeRestOfLine then
			if i < ExpectedCount then
				Shine:Print( "Take rest of line called on function expecting more arguments!" )
				Shine:NotifyCommandError( Client,
					"The author of this command misconfigured it. If you know them, tell them!" )

				return nil
			end

			ArgString = self.BuildLineFromArgs( Args, i )
		end

		local Success, Result = self:GetCommandArg( Client, ConCommand, ArgString, CurArg, i )
		if not Success then return nil end

		ParsedArgs[ i ] = Result
	end

	return ParsedArgs
end

--[[
	Executes a Shine command. Should not be called directly.
	Inputs: Client running the command, console command to run,
	string arguments passed to the command.
]]
function Shine:RunCommand( Client, ConCommand, FromChat, ... )
	local Command = self.Commands[ ConCommand ]
	if not Command or Command.Disabled then return end

	local Args = { ... }
	--In case someone was calling Shine:RunCommand() directly (even though it says "Should not be called directly.")
	if not IsType( FromChat, "boolean" ) then
		TableInsert( Args, 1, FromChat )
		FromChat = false
	end

	self.CommandStack[ #self.CommandStack + 1 ] = FromChat

	local ParsedArgs = self.CommandUtil:GetCommandArgs( Client, ConCommand, FromChat, Command, Args )
	if not ParsedArgs then
		PopCommandStack( self )
		return
	end

	local Success = xpcall( Command.Func, OnError, Client, unpack( ParsedArgs, 1, #Command.Arguments ) )

	PopCommandStack( self )

	if not Success then
		Shine:DebugPrint( "[Command Error] Console command %s failed.", true, ConCommand )
	else
		local Arguments = TableConcat( Args, " " )
		local Player = Client and Client:GetControllingPlayer()
		local Name = Player and Player:GetName() or "Console"
		local ID = Client and Client:GetUserId() or "N/A"

		self:AdminPrint( nil, "%s[%s] ran command %s %s", true,
			Name, ID, ConCommand,
			Arguments ~= "" and "with arguments: "..Arguments or "with no arguments." )
	end
end

Shine.Hook.Add( "PlayerSay", "CommandExecute", function( Client, Message )
	local Exploded = StringExplode( Message.message, " " )

	local Directive
	local FirstWord = Exploded[ 1 ]
	if not FirstWord then return end

	--They've done !, / or some other special character first.
	if StringFind( StringSub( FirstWord, 1, 1 ), "[^%w]" ) then
		Directive = StringSub( FirstWord, 1, 1 )
		Exploded[ 1 ] = StringSub( FirstWord, 2 )
	end

	if not Directive then return end

	local CommandObj = Shine.ChatCommands[ Exploded[ 1 ] ]
	if not CommandObj or CommandObj.Disabled then return end

	TableRemove( Exploded, 1 )

	Shine:RunCommand( Client, CommandObj.ConCmd, true, unpack( Exploded ) )

	if CommandObj.Silent then return "" end
	if Shine.Config.SilentChatCommands then return "" end
	if Directive == "/" then return "" end
end, -20 )
