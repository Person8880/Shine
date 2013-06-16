--[[
	Client side commands handling.
]]

local assert = assert
local setmetatable = setmetatable
local Round = math.Round
local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
local TableRemove = table.remove
local type = type

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
	assert( type( Table ) == "table", "Bad argument #1 to AddParam, table expected, got "..type( Table ) )

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
	Registers a Shine command.
	Inputs: Console command to assign, optional chat command to assign, function to run, optional silent flag to always be silent.
]]
function Shine:RegisterClientCommand( ConCommand, Function )
	assert( type( ConCommand ) == "string", "Bad argument #1 to RegisterCommand, string expected, got "..type( ConCommand ) )
	assert( type( Function ) == "function", "Bad argument #3 to RegisterCommand, function expected, got "..type( Function ) )

	local CmdObj = Command( ConCommand, Function )

	ClientCommands[ ConCommand ] = CmdObj

	if not HookedCommands[ ConCommand ] then --This prevents hooking again if a plugin is reloaded, which causes doubles or more of the command.
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
    if not Max then
        return Number > Min and Number or Min
    elseif not Min then
        return Number < Max and Number or Max
    elseif not Max and not Min then
        return Number
    else
        if Number < Min then return Min end
        if Number > Max then return Max end
        return Number
    end
end

local function isfunction( Func )
	return type( Func ) == "function"
end

--These define all valid command parameter types and how to process a string into the type.
local ParamTypes = {
	--Strings return simply the string (clipped to max length if given).
	string = function( String, Table ) 
		if not String or String == "" then return isfunction( Table.Default ) and Table.Default() or Table.Default end

		return Table.MaxLength and String:sub( 1, Table.MaxLength ) or String
	end,
	--Number performs tonumber() on the string and clamps the result between the given min and max if applicable. Also rounds if asked.
	number = function( String, Table )
		local Num = MathClamp( tonumber( String ), Table.Min, Table.Max )

		if not Num then
			return isfunction( Table.Default ) and Table.Default() or Table.Default
		end

		return Table.Round and Round( Num ) or Num
	end,
	--Boolean turns "false" and 0 into false and everything else into true.
	boolean = function( String, Table )
		if not String or String == "" then 
			if isfunction( Table.Default ) then
				return Table.Default() 
			else
				return Table.Default 
			end
		end

		local ToNum = tonumber( String )

		return ToNum and ToNum ~= 0 or String ~= "false"
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

--[[
	Executes a Shine command. Should not be called directly.
	Inputs: Client running the command, console command to run, string arguments passed to the command.
]]
function Shine:RunClientCommand( ConCommand, ... )
	local Command = ClientCommands[ ConCommand ]

	if not Command then return end

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
			Shared.Message( StringFormat( CurArg.Error or "Incorrect argument #%s to %s, expected %s.", i, ConCommand, CurArg.Type ) )

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
	Command.Func( unpack( ParsedArgs ) )
end
