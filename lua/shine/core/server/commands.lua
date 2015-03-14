--[[
	Shine console/chat command handling.
]]

local MathClamp = math.ClampEx
local Round = math.Round
local StringExplode = string.Explode
local StringFind = string.find
local StringFormat = string.format
local StringGSub = string.gsub
local TableConcat = table.concat
local TableRemove = table.remove
local TableSort = table.sort
local tostring = tostring
local type = type
local xpcall = xpcall

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
end

function CommandMeta:Help( HelpString )
	Shine.Assert( type( HelpString ) == "string",
		"Bad argument #1 to Help, string expected, got %s", type( HelpString ) )

	self.Help = HelpString
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
			return Shine:RunCommand( Client, ConCommand, ... )
		end )
		HookedCommands[ ConCommand ] = true
	end

	return CmdObj
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
local ParamTypes = Shine.CommandUtil.ParamTypes

--Client looks for a matching client by game ID, Steam ID and name. Returns 1 client.
ParamTypes.client = function( Client, String, Table )
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
end
--Clients looks for matching clients by game ID, Steam ID, name
--or special targeting directive. Returns a table of clients.
ParamTypes.clients = function( Client, String, Table )
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
end
--Team takes either 0 - 3 directly or takes a string matching a team name
--and turns it into the team number.
ParamTypes.team = function( Client, String, Table )
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
end

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

--[[
	Executes a Shine command. Should not be called directly.
	Inputs: Client running the command, console command to run,
	string arguments passed to the command.
]]
function Shine:RunCommand( Client, ConCommand, ... )
	local Command = self.Commands[ ConCommand ]

	if not Command or Command.Disabled then return end

	local Allowed, ArgRestrictions = self:GetPermission( Client, ConCommand )
	if not Allowed then
		self:NotifyError( Client, "You do not have permission to use %s.", true, ConCommand )

		return
	end

	local Player = Client or "Console"
	local Args = { ... }
	local ExpectedArgs = Command.Arguments
	local ExpectedCount = #ExpectedArgs

	if Args[ 1 ] == nil and ExpectedCount > 0 and not ExpectedArgs[ 1 ].Optional then
		if Client then
			ServerAdminPrint( Client, StringFormat( "%s - %s", ConCommand,
				Command.Help or "No help available." ) )
		else
			Print( "%s - %s", ConCommand, Command.Help or "No help available." )
		end

		return
	end

	local ParsedArgs = {}

	for i = 1, ExpectedCount do
		local CurArg = ExpectedArgs[ i ]

		--Convert the string argument into the requested type.
		local Result, Extra = ParseParameter( Client, Args[ i ], CurArg )
		ParsedArgs[ i ] = Result

		--Specifically check for nil (boolean argument could be false).
		if ParsedArgs[ i ] == nil and not CurArg.Optional then
			if CurArg.Type:find( "client" ) then
				if CurArg.Type == "client" and Extra then
					self:NotifyError( Player, "You cannot target yourself with this command." )
				else
					--No client means no match.
					self:NotifyError( Player, "No matching %s found.", true,
						CurArg.Type == "client" and "player was" or "players were" )
				end
			else
				self:NotifyError( Player,
					CurArg.Error or "Incorrect argument #%i to %s, expected %s.",
					true, i, ConCommand, CurArg.Type )
			end

			return
		end

		local ArgType = CurArg.Type
		local RestrictionIndex = tostring( i )

		if ArgRestrictions and ArgRestrictions[ RestrictionIndex ] then
			local Func = ArgValidators[ ArgType ]

			--Apply restrictions.
			if Func then
				ParsedArgs[ i ] = Func( Client, ParsedArgs[ i ],
					ArgRestrictions[ RestrictionIndex ] )

				--The restriction wiped the argument as it's not allowed.
				if ParsedArgs[ i ] == nil then
					self:NotifyError( Player,
						"Invalid argument #%i, restricted in rank settings.", true, i )

					return
				end
			end
		end

		--Take rest of line should grab the entire rest of the argument list.
		if ArgType == "string" and CurArg.TakeRestOfLine then
			if i == ExpectedCount then
				ParsedArgs[ i ] = self.CommandUtil.BuildLineFromArgs( CurArg, ParsedArgs[ i ],
					Args, i )
			else
				self:Print( "Take rest of line called on function expecting more arguments!" )
				self:NotifyError( Player,
					"The author of this command misconfigured it. If you know them, tell them!" )

				return
			end
		end

		--Ensure the calling client can target the return client.
		if ArgType == "client" and not CurArg.IgnoreCanTarget then
			if not self:CanTarget( Client, ParsedArgs[ i ] ) then
				self:NotifyError( Player, "You do not have permission to target %s.",
					true, ParsedArgs[ i ]:GetControllingPlayer():GetName() )

				return
			end
		end

		--Ensure the calling client can target every returned client.
		if ArgType == "clients" and not CurArg.IgnoreCanTarget then
			local ParsedArg = ParsedArgs[ i ]

			if ParsedArg then
				if #ParsedArg == 0 then
					self:NotifyError( Player, "No matching players found." )

					return
				end

				local Offset = 0
				for j = 1, #ParsedArg do
					local Key = j - Offset
					if not self:CanTarget( Client, ParsedArg[ Key ] ) then
						TableRemove( ParsedArg, Key )
						Offset = Offset + 1
					end
				end

				if #ParsedArg == 0 then
					self:NotifyError( Player,
						"You do not have permission to target anyone you specified." )

					return
				end
			end
		end
	end

	local Success = xpcall( Command.Func, OnError, Client, unpack( ParsedArgs ) )

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
	if FirstWord:sub( 1, 1 ):find( "[^%w]" ) then
		Directive = FirstWord:sub( 1, 1 )
		Exploded[ 1 ] = FirstWord:sub( 2 )
	end

	if not Directive then return end

	local CommandObj = Shine.ChatCommands[ Exploded[ 1 ] ]
	if not CommandObj or CommandObj.Disabled then return end

	TableRemove( Exploded, 1 )

	Shine:RunCommand( Client, CommandObj.ConCmd, unpack( Exploded ) )

	if CommandObj.Silent then return "" end
	if Shine.Config.SilentChatCommands then return "" end
	if Directive == "/" then return "" end
end, -20 )
