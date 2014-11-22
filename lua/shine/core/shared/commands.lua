--[[
	Shine console commands system.
]]

Shared.RegisterNetworkMessage( "Shine_Command", {
	Command = "string (255)"
} )

local IsType = Shine.IsType
local MathClamp = math.ClampEx
local StringFormat = string.format
local StringUTF8Sub = string.UTF8Sub
local TableConcat = table.concat

Shine.CommandUtil = {}

local function GetDefault( Table )
	if IsType( Table.Default, "function" ) then
		return Table.Default()
	end

	return Table.Default
end
Shine.CommandUtil.GetDefaultValue = GetDefault

Shine.CommandUtil.ParamTypes = {
	--Strings return simply the string (clipped to max length if given).
	string = function( Client, String, Table ) 
		if not String or String == "" then
			return GetDefault( Table )
		end

		return Table.MaxLength and String:UTF8Sub( 1, Table.MaxLength ) or String
	end,
	--Number performs tonumber() on the string and clamps the result between
	--the given min and max if set. Also rounds if asked.
	number = function( Client, String, Table )
		local Num = MathClamp( tonumber( String ), Table.Min, Table.Max )

		if not Num then
			return GetDefault( Table )
		end

		return Table.Round and Round( Num ) or Num
	end,
	--Boolean turns "false" and 0 into false and everything else into true.
	boolean = function( Client, String, Table )
		if not String or String == "" then 
			return GetDefault( Table )
		end

		local ToNum = tonumber( String )

		if ToNum then
			return ToNum ~= 0
		end

		return String ~= "false"
	end
}
local ParamTypes = Shine.CommandUtil.ParamTypes

function Shine.CommandUtil.ParseParameter( Client, String, Table )
	local Type = Table.Type
	if not ParamTypes[ Type ] then
		return nil
	end

	if String then
		return ParamTypes[ Type ]( Client, String, Table )
	else
		if not Table.Optional then return nil end
		return ParamTypes[ Type ]( Client, String, Table )
	end
end

function Shine.CommandUtil.BuildLineFromArgs( CurArg, ParsedArg, Args, i )
	local Rest = TableConcat( Args, " ", i + 1 )

	if Rest ~= "" then
		ParsedArg = StringFormat( "%s %s", ParsedArg, Rest )
	end

	if CurArg.MaxLength then
		ParsedArg = StringUTF8Sub( ParsedArg, 1, CurArg.MaxLength )
	end

	return ParsedArg
end

if Server then return end

Client.HookNetworkMessage( "Shine_Command", function( Message )
	Shared.ConsoleCommand( Message.Command )
end )
