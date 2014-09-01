--[[
	Client side commands handling.
]]

local Notify = Shared.Message
local setmetatable = setmetatable
local Round = math.Round
local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
local TableRemove = table.remove
local Traceback = debug.traceback
local type = type
local xpcall = xpcall

--[[
	Command object.
	Stores the console command and the function to run when these commands are used.
]]
local CommandMeta = {}
CommandMeta.__index = CommandMeta

--[[
	Adds a parameter to a command. This defines what an argument should be parsed into.
]]
function CommandMeta:AddParam( Table )
	Shine.Assert( type( Table ) == "table",
		"Bad argument #1 to AddParam, table expected, got %s", type( Table ) )

	local Args = self.Arguments
	Args[ #Args + 1 ] = Table
end

--[[
	Creates a command object. 
	The object stores the console command and the function to run.
	It can also have parameters added to it to pass to its function.
]]
local function Command( ConCommand, Function )
	return setmetatable( {
		ConCmd = ConCommand,
		Func = Function,
		Arguments = {}
	}, CommandMeta )
end

local HookedCommands = {}

local ClientCommands = {}
Shine.ClientCommands = ClientCommands

--[[
	Registers a Shine client side command.
	Inputs: Console command to assign, function to run.
]]
function Shine:RegisterClientCommand( ConCommand, Function )
	self.Assert( type( ConCommand ) == "string",
		"Bad argument #1 to RegisterClientCommand, string expected, got %s", type( ConCommand ) )
	self.Assert( type( Function ) == "function",
		"Bad argument #2 to RegisterClientCommand, function expected, got %s", type( Function ) )

	local CmdObj = Command( ConCommand, Function )

	ClientCommands[ ConCommand ] = CmdObj

	if not HookedCommands[ ConCommand ] then
		Event.Hook( "Console_"..ConCommand, function( ... )
			return Shine:RunClientCommand( ConCommand, ... )
		end )

		HookedCommands[ ConCommand ] = true
	end

	return CmdObj
end

function Shine:RemoveClientCommand( ConCommand )
	ClientCommands[ ConCommand ] = nil
end

--More generic clamp for use with the number argument type.
local function MathClamp( Number, Min, Max )
    if not Number then return nil end
    if not Max and Min then
        return Number > Min and Number or Min
    elseif not Min and Max then
        return Number < Max and Number or Max
    elseif not Max and not Min then
        return Number
    else
        if Number < Min then return Min end
        if Number > Max then return Max end
        return Number
    end
end

local IsType = Shine.IsType

--These define all valid command parameter types and how to process a string into the type.
local ParamTypes = {
	--Strings return simply the string (clipped to max length if given).
	string = function( String, Table ) 
		if not String or String == "" then
			return IsType( Table.Default, "function" ) and Table.Default() or Table.Default
		end

		return Table.MaxLength and String:UTF8Sub( 1, Table.MaxLength ) or String
	end,
	--Number performs tonumber() on the string and clamps the result between the given min and max.
	number = function( String, Table )
		local Num = MathClamp( tonumber( String ), Table.Min, Table.Max )

		if not Num then
			return IsType( Table.Default, "function" ) and Table.Default() or Table.Default
		end

		return Table.Round and Round( Num ) or Num
	end,
	--Boolean turns "false" and 0 into false and everything else into true.
	boolean = function( String, Table )
		if not String or String == "" then 
			if IsType( Table.Default, "function" ) then
				return Table.Default() 
			else
				return Table.Default 
			end
		end

		local ToNum = tonumber( String )

		if ToNum then
			return ToNum ~= 0
		end

		return String ~= "false"
	end
}

--[[
	Parses the given string using the given parameter table and returns the result.
	Inputs: Client, string argument, parameter table.
	Output: Converted argument or nil.
]]
local function ParseParameter( String, Table )
    local Type = Table.Type
    if String then
        return ParamTypes[ Type ] and ParamTypes[ Type ]( String, Table )
    else
        if not Table.Optional then return nil end
        return ParamTypes[ Type ] and ParamTypes[ Type ]( String, Table )
    end
end

local function OnError( Error )
	local Trace = Traceback()

	Shine:DebugPrint( "Error: %s.\n%s", true, Error, Trace )
	Shine:AddErrorReport( StringFormat( "Client command error: %s.", Error ), Trace )
end

--[[
	Executes a client side Shine command. Should not be called directly.
	Inputs: Console command to run, string arguments passed to the command.
]]
function Shine:RunClientCommand( ConCommand, ... )
	local Command = ClientCommands[ ConCommand ]

	if not Command then return end

	if Command.Disabled then return end

	local Args = { ... }

	local ParsedArgs = {}
	local ExpectedArgs = Command.Arguments
	local ExpectedCount = #ExpectedArgs

	for i = 1, ExpectedCount do
		local CurArg = ExpectedArgs[ i ]

		--Convert the string argument into the requested type.
		ParsedArgs[ i ] = ParseParameter( Args[ i ], CurArg )

		--Specifically check for nil (boolean argument could be false).
		if ParsedArgs[ i ] == nil and not CurArg.Optional then
			Notify( StringFormat( CurArg.Error or "Incorrect argument #%s to %s, expected %s.",
				i, ConCommand, CurArg.Type ) )

			return
		end

		--Take rest of line should grab the entire rest of the argument list.
		if CurArg.Type == "string" and CurArg.TakeRestOfLine then
			if i == ExpectedCount then
				local Rest = TableConcat( Args, " ", i + 1 )

				if Rest ~= "" then
					ParsedArgs[ i ] = ParsedArgs[ i ].." "..Rest
				end

				if CurArg.MaxLength then
					ParsedArgs[ i ] = ParsedArgs[ i ]:sub( 1, CurArg.MaxLength )
				end
			else
				error( "Take rest of line called on function expecting more arguments!" )

				return
			end
		end
	end

	--Run the command with the parsed arguments we've gathered.
	local Success = xpcall( Command.Func, OnError, unpack( ParsedArgs ) )

	if not Success then
		Shine:DebugPrint( "An error occurred when running the command: '%s'.", true, ConCommand )
	end
end
