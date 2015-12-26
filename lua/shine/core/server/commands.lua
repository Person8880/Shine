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
	OnFailedMatch = function( Client, Arg, SelfTargeting, ArgString )
		if SelfTargeting then
			Shine:NotifyCommandError( Client, "You cannot target yourself with this command." )
		else
			Shine:NotifyCommandError( Client, "No player matching '%s' was found.", true, ArgString )
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

do
	local TeamDefs = {
		[ "spectate" ] = 3,
		[ "spectator" ] = 3,
		[ "readyroom" ] = kTeamReadyRoom,
		[ "rr" ] = kTeamReadyRoom,
		[ "marine" ] = 1,
		[ "alien" ] = 2,
		[ "blue" ] = 1,
		[ "orange" ] = 2,
		[ "gold" ] = 2
	}

	local function ParseValue( Client, Value, Context, ControlCharacters )
		local CurrentTargets = {}
		local Negate

		-- If the first character is a !, then it's a negation.
		local ControlChar = StringSub( Value, 1, 1 )
		if ControlChar == "!" then
			Value = StringSub( Value, 2 )
			ControlChar = StringSub( Value, 1, 1 )
			Negate = true
		end

		Context.IsNegative = Negate

		local Parser = ControlCharacters[ ControlChar ]
		if Parser and ( not Parser.MustEqual or Value == ControlChar ) then
			Context.Value = StringSub( Value, 2 )

			local Targets = Parser.Parse( Client, Context )
			if Targets then
				for i = 1, #Targets do
					CurrentTargets[ Targets[ i ] ] = true
				end

				return CurrentTargets
			end
		end

		local Target = Shine:GetClient( Value )
		if not Target then return CurrentTargets end

		CurrentTargets[ Target ] = true

		return CurrentTargets
	end

	local function AddToTargets( CurrentTargets, Context )
		local Targets = Context.Targets

		if Context.IsNegative then
			-- If this is the first target specifier, then negate from all connected clients.
			if Context.ValueIndex == 1 then
				for j = 1, Context.NumClients do
					local Target = Context.AllClients[ j ]

					if not CurrentTargets[ Target ] then
						Targets[ Target ] = true
					end
				end
			else
				for Target in pairs( CurrentTargets ) do
					Targets[ Target ] = nil
				end
			end
		else
			for Target in pairs( CurrentTargets ) do
				Targets[ Target ] = true
			end
		end
	end

	-- Clients looks for matching clients by game ID, Steam ID, name
	-- or special targeting directive. Returns a table of clients.
	ParamTypes.clients = {
		TeamDefs = TeamDefs, -- If anyone ever has teams in their mod, you can add to this.
		ControlCharacters = {
			[ "%" ] = {
				-- Finds by user group name.
				Parse = function( Client, Context )
					return Shine:GetClientsByGroup( Context.Value )
				end
			},
			[ "$" ] = {
				-- Finds by NS2/Steam ID.
				Parse = function( Client, Context )
					local NS2ID = tonumber( Context.Value )
					local Target

					if NS2ID then
						Target = Shine.GetClientByNS2ID( NS2ID )
					else
						Target = Shine:GetClientBySteamID( Context.Value )
					end

					return { Target }
				end
			},
			[ "@" ] = {
				-- Finds by team name.
				Parse = function( Client, Context )
					local TeamIndex = TeamDefs[ Context.Value ]
					if not TeamIndex then
						return nil
					end

					return Shine.GetTeamClients( TeamIndex )
				end
			},
			[ "*" ] = {
				-- Matches all clients connected.
				Parse = function( Client, Context )
					return Context.AllClients
				end,
				MustEqual = true
			},
			[ "^" ] = {
				-- Matches the calling client.
				Parse = function( Client, Context )
					return { Client }
				end,
				MustEqual = true
			}
		},
		Parse = function( Client, String, Table )
			if not String then
				return GetDefault( Table )
			end

			local Values = StringExplode( String, "," )
			local Targets = {}

			local AllClients, NumClients = Shine.GetAllClients()
			local Context = {
				AllClients = AllClients,
				NumClients = NumClients,
				ArgDef = Table,
				Targets = Targets
			}

			local ControlCharacters = ParamTypes.clients.ControlCharacters

			for i = 1, #Values do
				Context.ValueIndex = i

				local CurrentTargets = ParseValue( Client, Values[ i ], Context, ControlCharacters )
				AddToTargets( CurrentTargets, Context )
			end

			if Table.NotSelf and Targets[ Client ] then
				Targets[ Client ] = nil
			end

			local Clients = {}
			for Target in pairs( Targets ) do
				Clients[ #Clients + 1 ] = Target
			end

			return Clients
		end,
		Help = "players",
		OnFailedMatch = function( Client, Arg, Extra, ArgString )
			Shine:NotifyCommandError( Client, "No players matching '%s' were found.", true, ArgString )
		end,
		Validate = function( Client, Arg, ParsedArg, ArgString )
			if not ParsedArg then return true end
			if #ParsedArg == 0 then
				Shine:NotifyCommandError( Client, "No players matching '%s' were found.", true, ArgString )

				return false
			end

			if Arg.IgnoreCanTarget then return true end

			Shine.Stream( ParsedArg ):Filter( function( Value )
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
end

do
	local TeamMatches = {
		{ "ready", 0 },
		{ "marine", 1 },
		{ "alien", 2 },
		{ "spectat", 3 },
		{ "blu", 1 },
		{ "orang", 2 },
		{ "gold", 2 },
		{ "^rr", 0 }
	}

	local StringLower = string.lower

	-- Team takes either 0 - 3 directly or takes a string matching a team name
	-- and turns it into the team number.
	ParamTypes.team = {
		Parse = function( Client, String, Table )
			if not String then
				return GetDefault( Table )
			end

			local TeamNumber = tonumber( String )
			if TeamNumber then return MathClamp( Round( TeamNumber ), 0, 3 ) end

			String = StringLower( String )

			for i = 1, #TeamMatches do
				if StringFind( String, TeamMatches[ i ][ 1 ] ) then
					return TeamMatches[ i ][ 2 ]
				end
			end

			return nil
		end,
		Help = "team"
	}
end

ParamTypes.steamid = {
	Parse = function( Client, String, Table )
		local NS2ID = tonumber( String )
		if NS2ID then return NS2ID end

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

local function MatchStringRestriction( ParsedArg, Restriction )
	if not StringFind( Restriction, "*" ) then
		return ParsedArg == Restriction
	end

	-- Escape any patterns in the string.
	Restriction = StringGSub( Restriction, "([%%%[%]%^%$%(%)%.%+%-%?])", "%%%1" )
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

function Shine.CommandUtil:Validate( Client, ConCommand, Result, MatchedType, CurArg, i )
	-- Yes, it's repeating it, but getting permissions is pretty much free once cached.
	local Allowed, ArgRestrictions = Shine:GetPermission( Client, ConCommand )
	if not ArgRestrictions then return true end

	local RestrictionIndex = tostring( i )
	if not ArgRestrictions[ RestrictionIndex ] then return true end

	local Func = ArgValidators[ MatchedType ]
	if not Func then return true end

	Result = Func( Client, Result, ArgRestrictions[ RestrictionIndex ] )

	--The restriction wiped the argument as it's not allowed.
	if Result == nil then
		Shine:NotifyCommandError( Client,
			"Invalid argument #%i, restricted in rank settings.", true, i )

		return false
	end

	return true, Result
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

local OnError = Shine.BuildErrorHandler( "Command error" )

--[[
	Executes a Shine command. Should not be called directly.
	Inputs: Client running the command, console command to run,
	string arguments passed to the command.
]]
function Shine:RunCommand( Client, ConCommand, FromChat, ... )
	local Command = self.Commands[ ConCommand ]
	if not Command or Command.Disabled then return end

	local OriginalArgs = { ... }
	--In case someone was calling Shine:RunCommand() directly (even though it says "Should not be called directly.")
	if not IsType( FromChat, "boolean" ) then
		TableInsert( OriginalArgs, 1, FromChat )
		FromChat = false
	end

	Args = self.CommandUtil.AdjustArguments( OriginalArgs )

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
		local Arguments = TableConcat( OriginalArgs, " " )
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
