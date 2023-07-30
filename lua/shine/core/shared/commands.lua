--[[
	Shine console commands system.
]]

local Shine = Shine

Shared.RegisterNetworkMessage( "Shine_Command", {
	Command = "string (255)"
} )
Shared.RegisterNetworkMessage( "Shine_TranslatedCommandError", {
	MessageKey = "string (32)",
	Source = "string (20)",
	IsConsole = "boolean"
} )

local IsType = Shine.IsType
local MathsClamp = math.Clamp
local MathsClampEx = math.ClampEx
local MathsFloor = math.floor
local StringExplode = string.Explode
local StringFormat = string.format
local StringToTime = string.ToTime
local StringUpper = string.upper
local StringUTF8Sub = string.UTF8Sub
local TableConcat = table.concat

do
	local function GetNetworkMessageName( Name, Source )
		return StringFormat( "Shine_CommandNotify_%s%s", Source or "", Name )
	end

	local function ApplyErrorMessage( Message, IsConsole )
		if IsConsole then
			if Shine.AdminMenu:GetIsVisible() then
				-- The admin menu is counted as executing through the console, so we need to notify the
				-- user.
				Shine.GUI.NotificationManager.AddNotification( Shine.NotificationType.ERROR, Message, 5 )
			end

			Shared.Message( StringFormat( "%s %s", Shine.Locale:GetPhrase( "Core", "ERROR_TAG" ), Message ) )
		else
			Shine:NotifyError( Message )
		end
	end

	function Shine.RegisterTranslatedCommandError( Name, Data, Source, Options )
		local MessageName = GetNetworkMessageName( Name, Source )
		Data.IsConsole = "boolean"
		Shared.RegisterNetworkMessage( MessageName, Data )

		if Server then return end

		local VariationKey = Options and Options.VariationKey

		Shine.HookNetworkMessage( MessageName, function( Data )
			local MessageKey = VariationKey and StringFormat( "%s_%s", Name, Data[ VariationKey ] ) or Name
			local Message = Shine.Locale:GetInterpolatedPhrase( Source or "Core", MessageKey, Data )
			ApplyErrorMessage( Message, Data.IsConsole )
		end )
	end

	if Server then
		function Shine:SendTranslatedCommandError( Client, Name, Data, Source, ToConsole )
			if ToConsole ~= nil then
				Data.IsConsole = ToConsole
			else
				Data.IsConsole = not self:IsCommandFromChat()
			end
			self:ApplyNetworkMessage( Client, GetNetworkMessageName( Name, Source ), Data, true )
		end
	else
		Shine.HookNetworkMessage( "Shine_TranslatedCommandError", function( Data )
			local Source = Data.Source
			if Source == "" then
				Source = "Core"
			end
			local Message = Shine.Locale:GetPhrase( Source, Data.MessageKey )
			ApplyErrorMessage( Message, Data.IsConsole )
		end )
	end

	local ErrorMessages = {
		PlayerName = {
			PlayerName = StringFormat( "string (%i)", kMaxNameLength * 4 + 1 )
		},
		BadArgument = {
			ArgNum = "integer (1 to 32)",
			CommandName = "string (24)",
			ExpectedType = "string (32)"
		},
		ArgNum = {
			ArgNum = "integer (1 to 32)"
		},
		CommandName = {
			CommandName = "string (24)"
		}
	}

	local Errors = {
		ERROR_NO_MATCHING_PLAYER = ErrorMessages.PlayerName,
		ERROR_NO_MATCHING_PLAYERS = ErrorMessages.PlayerName,
		ERROR_CANT_TARGET = ErrorMessages.PlayerName,
		COMMAND_DEFAULT_ERROR = ErrorMessages.BadArgument,
		COMMAND_RESTRICTED_ARG = ErrorMessages.ArgNum,
		COMMAND_NO_PERMISSION = ErrorMessages.CommandName
	}

	for Key, Data in pairs( Errors ) do
		Shine.RegisterTranslatedCommandError( Key, Data )
	end
end

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
	-- Strings return simply the string (clipped to max length if given).
	string = {
		Parse = function( Client, String, Table )
			if not String or String == "" then
				return GetDefault( Table )
			end

			return Table.MaxLength and StringUTF8Sub( String, 1, Table.MaxLength ) or String
		end,
		Help = "string"
	},
	-- Number performs tonumber() on the string and clamps the result between
	-- the given min and max if set. Also rounds if asked.
	number = {
		Parse = function( Client, String, Table )
			local Num = MathsClampEx( tonumber( String ), Table.Min, Table.Max )

			if not Num then
				return GetDefault( Table )
			end

			return Table.Round and Round( Num ) or Num
		end,
		Help = "number"
	},
	-- Time value, either a direct number or a "nice" string value.
	-- Units can be specified if seconds are not desired.
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

			Time = MathsClampEx( Time, Table.Min, Table.Max )

			return Table.Round and Round( Time ) or Time
		end,
		Help = function( Arg ) return StringFormat( "duration in %s", Arg.Units or "seconds" ) end
	},
	-- Boolean turns "false" and 0 into false and everything else into true.
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
	},
	-- Returns a value from a lookup table, either as an upper case key, or a number.
	enum = {
		Parse = function( Client, String, Table )
			local PossibleValues
			if IsType( Table.Values, "function" ) then
				PossibleValues = Table.Values()
			else
				PossibleValues = Table.Values
			end

			local EnumValue = PossibleValues[ StringUpper( String ) ] or PossibleValues[ tonumber( String ) ]
			if EnumValue then
				return EnumValue
			end

			return GetDefault( Table )
		end,
		Help = function( Arg ) return StringFormat( "[ %s ]", TableConcat( Arg.Values, ", " ) ) end,
		GetAutoCompletions = function( Arg )
			return Arg.Values
		end
	},
	colour = {
		Parse = function( Client, String, Table )
			if not String or String == "" then
				return GetDefault( Table )
			end

			-- Accept comma and/or spaces as separators (spaces can be used if TakeRestOfLine is enabled on the arg).
			local Components = StringExplode( String, "[%s,]" )
			local Colour = { 255, 255, 255 }
			for i = 1, 3 do
				Colour[ i ] = MathsClamp( MathsFloor( tonumber( Components[ i ] ) ) or 255, 0, 255 )
			end
			return Colour
		end,
		Help = "colour"
	}
}

do
	local TeamMatches = {
		{ "ready", 0 },
		{ "marine", 1 },
		{ "frontier", 1 },
		{ "alien", 2 },
		{ "khara", 2 },
		{ "spectat", 3 },
		{ "blu", 1 },
		{ "orang", 2 },
		{ "gold", 2 },
		{ "^rr", 0 }
	}

	local StringFind = string.find
	local StringLower = string.lower

	local TeamNames = {
		"marine", "alien", "spectate", "rr", "ready room", "frontiersmen", "khara", "blue", "orange", "gold",
		"0", "1", "2", "3"
	}

	-- Team takes either 0 - 3 directly or takes a string matching a team name
	-- and turns it into the team number.
	Shine.CommandUtil.ParamTypes.team = {
		Parse = function( Client, String, Table )
			if not String then
				return GetDefault( Table )
			end

			local TeamNumber = tonumber( String )
			if TeamNumber then return MathsClampEx( Round( TeamNumber ), 0, 3 ) end

			String = StringLower( String )

			for i = 1, #TeamMatches do
				if StringFind( String, TeamMatches[ i ][ 1 ] ) then
					return TeamMatches[ i ][ 2 ]
				end
			end

			return nil
		end,
		Help = "team",
		GetAutoCompletions = function()
			return TeamNames
		end
	}
end
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

function Shine.CommandUtil.GetExpectedValue( CurArg )
	local ParamType = ParamTypes[ CurArg.Type ]
	local ExpectedValue = CurArg.Type
	if IsType( ExpectedValue, "table" ) then
		ExpectedValue = TableConcat( ExpectedValue, " or " )
	end

	if ParamType and ParamType.Help then
		if IsType( ParamType.Help, "function" ) then
			ExpectedValue = ParamType.Help( CurArg )
		else
			ExpectedValue = ParamType.Help
		end
	end

	return ExpectedValue
end

function Shine.CommandUtil:GetCommandArg( Client, ConCommand, ArgString, CurArg, i )
	-- Convert the string argument into the requested type.
	local Result, Extra, MatchedType = self.ParseParameter( Client, ArgString, CurArg )
	MatchedType = MatchedType or CurArg.Type

	local ParamType = ParamTypes[ MatchedType ]

	-- Specifically check for nil (boolean argument could be false).
	if Result == nil and not CurArg.Optional then
		if ParamType.OnFailedMatch then
			ParamType.OnFailedMatch( Client, CurArg, Extra, ArgString )
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

	if ParamType.Validate and not ParamType.Validate( Client, CurArg, Result, ArgString ) then return end

	return true, Result
end

function Shine.CommandUtil.BuildLineFromArgs( Args, i )
	return TableConcat( Args, " ", i )
end

do
	local StringEndsWith = string.EndsWith
	local StringGMatch = string.gmatch
	local StringGSub = string.gsub
	local StringLen = string.len
	local StringMatch = string.match
	local StringStartsWith = string.StartsWith
	local StringSub = string.sub

	local function RemoveQuotes( String )
		-- If the quote wasn't terminated, go to the end of the string.
		local EndIndex = StringLen( String ) - ( StringEndsWith( String, "\"" ) and 1 or 0 )
		String = StringSub( String, 2, EndIndex )
		return StringGSub( String, "\\\"", "\"" )
	end

	local function GetArgBetweenQuotes( Args, StartIndex, EndIndex )
		-- Add all text between the quotes, not including the quotes.
		local String = TableConcat( Args, " ", StartIndex, EndIndex )
		return RemoveQuotes( String )
	end

	--[[
		Takes arguments bounded by quotes as a single argument.
	]]
	function Shine.CommandUtil.AdjustArguments( Args )
		local RealArgs = {}
		local Count = 0
		local StartIndex

		for i = 1, #Args do
			local Arg = Args[ i ]

			if StartIndex then
				if StringMatch( Arg, "[^\\]\"$" ) then
					Count = Count + 1
					RealArgs[ Count ] = GetArgBetweenQuotes( Args, StartIndex, i )
					StartIndex = nil
				end
			elseif StringStartsWith( Arg, "\"" ) then
				if StringMatch( Arg, "[^\\]\"$" ) then
					Count = Count + 1
					RealArgs[ Count ] = RemoveQuotes( Arg )
				else
					StartIndex = i
				end
			else
				Count = Count + 1
				RealArgs[ Count ] = Arg
			end
		end

		if StartIndex then
			Count = Count + 1
			RealArgs[ Count ] = GetArgBetweenQuotes( Args, StartIndex, #Args )
		end

		return RealArgs
	end

	local function ApplyQuotesIfNecessary( Text )
		if StringMatch( Text, "%s+" ) then
			return StringFormat( "\"%s\"", ( StringGSub( Text, "\"", "\\\"" ) ) )
		end
		return Text
	end

	function Shine.CommandUtil.SerialiseArguments( Args )
		return Shine.Stream( Args ):Map( ApplyQuotesIfNecessary ):Concat( " " )
	end

	function Shine.CommandUtil.SplitParameterHelp( ParameterHelp )
		local Arguments = {}

		-- Each argument is surrounded with either () or <>
		for Arg in StringGMatch( ParameterHelp, "([<(].-[)>])" ) do
			Arguments[ #Arguments + 1 ] = Arg
		end

		return Arguments
	end
end

do
	local StringLower = string.lower

	--[[
		Command object.
	]]
	local CommandMeta = {}
	CommandMeta.__index = CommandMeta

	--[[
		Adds a parameter to a command. This defines what an argument should be parsed into.
		For instance, a paramter of type "client" will be parsed into a client
		from their name or Steam ID.
	]]
	function CommandMeta:AddParam( Param )
		Shine.TypeCheck( Param, "table", 1, "AddParam" )
		Shine.TypeCheckField( Param, "Type", { "string", "table" }, "Param" )

		if IsType( Param.Type, "string" ) then
			Param.Type = StringLower( Param.Type )
			Shine.AssertAtLevel( ParamTypes[ Param.Type ], "Unknown parameter type: %s", 3, Param.Type )
		else
			Shine.AssertAtLevel( #Param.Type > 0, "Must provide at least 1 parameter type.", 3 )
			for i = 1, #Param.Type do
				local Type = Param.Type[ i ]
				Shine.AssertAtLevel( IsType( Type, "string" ), "Parameter types must be strings", 3 )

				Type = StringLower( Type )
				Param.Type[ i ] = Type

				Shine.AssertAtLevel( ParamTypes[ Type ], "Unknown parameter type: %s", 3, Type )
			end
		end

		local Args = self.Arguments
		Args[ #Args + 1 ] = Param

		return self
	end

	Shine.Command = CommandMeta
end

if Server then return end

Shine.HookNetworkMessage( "Shine_Command", function( Message )
	Shared.ConsoleCommand( Message.Command )
end )
