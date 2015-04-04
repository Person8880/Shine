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
	string = function( Client, String, Table )
		if not String or String == "" then
			return GetDefault( Table )
		end

		return Table.MaxLength and StringUTF8Sub( String, 1, Table.MaxLength ) or String
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
	--Time value, either a direct number or a "nice" string value.
	--Units can be specified if seconds are not desired.
	time = function( Client, String, Table )
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

function Shine.CommandUtil.BuildLineFromArgs( Args, i )
	return TableConcat( Args, " ", i )
end

if Server then return end

Client.HookNetworkMessage( "Shine_Command", function( Message )
	Shared.ConsoleCommand( Message.Command )
end )
