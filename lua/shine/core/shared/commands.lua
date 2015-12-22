--[[
	Shine console commands system.
]]

Shared.RegisterNetworkMessage( "Shine_Command", {
	Command = "string (255)"
} )

local IsType = Shine.IsType
local MathClamp = math.ClampEx
local StringFormat = string.format
local StringToTime = string.ToTime
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

local UnitConverters = {
	minutes = function( Seconds ) return Seconds / 60 end,
	hours = function( Seconds ) return Seconds / 3600 end,
	days = function( Seconds ) return Seconds / 86400 end,
	weeks = function( Seconds ) return Seconds / 604800 end
}
local function TimeToUnits( Seconds, Units )
	local Converter = UnitConverters[ Units ]
	if not Converter then return Seconds end

	return Converter( Seconds )
end

Shine.CommandUtil.ParamTypes = {
	--Strings return simply the string (clipped to max length if given).
	string = {
		Parse = function( Client, String, Table )
			if not String or String == "" then
				return GetDefault( Table )
			end

			return Table.MaxLength and StringUTF8Sub( String, 1, Table.MaxLength ) or String
		end,
		Help = "string"
	},
	--Number performs tonumber() on the string and clamps the result between
	--the given min and max if set. Also rounds if asked.
	number = {
		Parse = function( Client, String, Table )
			local Num = MathClamp( tonumber( String ), Table.Min, Table.Max )

			if not Num then
				return GetDefault( Table )
			end

			return Table.Round and Round( Num ) or Num
		end,
		Help = "number"
	},
	--Time value, either a direct number or a "nice" string value.
	--Units can be specified if seconds are not desired.
	time = {
		Parse = function( Client, String, Table )
			if not String or String == "" then
				return GetDefault( Table )
			end

			local Time = tonumber( String )
			if not Time then
				Time = StringToTime( String )
				if Table.Units then
					Time = TimeToUnits( Time, Table.Units )
				end
			end

			Time = MathClamp( Time, Table.Min, Table.Max )

			return Table.Round and Round( Time ) or Time
		end,
		Help = function( Arg ) return StringFormat( "duration in %s", Arg.Units or "seconds" ) end
	},
	--Boolean turns "false" and 0 into false and everything else into true.
	boolean = {
		Parse = function( Client, String, Table )
			if not String or String == "" then
				return GetDefault( Table )
			end

			local ToNum = tonumber( String )

			if ToNum then
				return ToNum ~= 0
			end

			return String ~= "false"
		end,
		Help = "boolean"
	}
}
local ParamTypes = Shine.CommandUtil.ParamTypes

local function ParseByType( Client, String, Table, Type )
	if not ParamTypes[ Type ] then
		return nil
	end

	return ParamTypes[ Type ].Parse( Client, String, Table )
end

function Shine.CommandUtil.ParseParameter( Client, String, Table )
	if not String and not Table.Optional then return nil end

	-- Single typed value.
	local Type = Table.Type
	if IsType( Type, "string" ) then
		return ParseByType( Client, String, Table, Type )
	end

	-- Multi-type value, take the first parse that succeeds.
	for i = 1, #Type do
		local Value, Extra = ParseByType( Client, String, Table, Type[ i ] )
		if Value ~= nil then
			return Value, Extra, Type[ i ]
		end
	end

	-- If none succeed, then use the first type as the failure point.
	return nil, nil, Type[ 1 ]
end

function Shine.CommandUtil:GetCommandArg( Client, ConCommand, ArgString, CurArg, i )
	-- Convert the string argument into the requested type.
	local Result, Extra, MatchedType = self.ParseParameter( Client, ArgString, CurArg )
	MatchedType = MatchedType or CurArg.Type

	local ParamType = ParamTypes[ MatchedType ]

	-- Specifically check for nil (boolean argument could be false).
	if Result == nil and not CurArg.Optional then
		if ParamType.OnFailedMatch then
			ParamType.OnFailedMatch( Client, CurArg, Extra )
		else
			self:OnFailedMatch( Client, ConCommand, ArgString, CurArg, i )
		end

		return
	end

	local Success, NewResult = self:Validate( Client, ConCommand, Result, MatchedType, CurArg, i )
	if not Success then return end

	if NewResult ~= nil then
		Result = NewResult
	end

	if ParamType.Validate and not ParamType.Validate( Client, CurArg, Result ) then return end

	return true, Result
end

function Shine.CommandUtil.BuildLineFromArgs( Args, i )
	return TableConcat( Args, " ", i )
end

if Server then return end

Client.HookNetworkMessage( "Shine_Command", function( Message )
	Shared.ConsoleCommand( Message.Command )
end )
