--[[
	Server rates configuration.
]]

local IsType = Shine.IsType
local Notify = Shared.Message
local StringFormat = string.format

local RatesModule = {}
RatesModule.DefaultConfig = {
	Rates = {
		-- Whether to enforce these rate settings or leave the defaults as-is.
		ApplyRates = true,
		BWLimit = 50,
		Interp = 100,
		MoveRate = 26,
		SendRate = 20,
		TickRate = 30
	}
}

local Rates = {
	{
		Key = "MoveRate",
		Min = 5,
		Integer = true,
		Default = 26,
		Command = "mr %s"
	},
	{
		Key = "TickRate",
		Min = 5,
		Integer = true,
		Default = function() return Server.GetTickrate() end,
		Command = "tickrate %s"
	},
	{
		Key = "SendRate",
		Integer = true,
		Min = 5,
		Default = function() return Server.GetSendrate() end,
		Command = "sendrate %s"
	},
	{
		Key = "Interp",
		Min = 0,
		Default = 100,
		Command = function( Value ) return StringFormat( "interp %s", Value * 0.001 ) end
	},
	{
		Key = "BWLimit",
		Min = 5,
		Transformer = function( Value ) return Value * 1024 end,
		Default = function() return Server.GetBwLimit() / 1024 end,
		Command = "bwlimit %s",
		WarnIfBelow = 50
	}
}

local Validator = Shine.Validator()
Validator:AddFieldRule( "Rates.ApplyRates", Validator.IsType( "boolean", true ) )
for i = 1, #Rates do
	local Rate = Rates[ i ]
	local Default = IsType( Rate.Default, "function" ) and Rate.Default() or Rate.Default
	local FieldName = "Rates."..Rate.Key

	Validator:AddFieldRule( FieldName, Validator.IsType( "number", Default ) )
	Validator:AddFieldRule( FieldName, Validator.Min( Rate.Min ) )
	if Rate.Integer then
		Validator:AddFieldRule( FieldName, Validator.Integer() )
	end
end

Validator:AddRule( {
	Matches = function( self, Config )
		return Config.Rates.MoveRate > Config.Rates.TickRate
	end,
	Fix = function( self, Config )
		Config.Rates.MoveRate = Config.Rates.TickRate
		Notify( "Move rate cannot be more than tick rate. Clamping to tick rate." )
	end
} )
Validator:AddRule( {
	Matches = function( self, Config )
		return Config.Rates.SendRate > Config.Rates.TickRate
	end,
	Fix = function( self, Config )
		Config.Rates.SendRate = Config.Rates.TickRate
		Notify( "Send rate cannot be more than tick rate. Clamping to tick rate." )
	end
} )
Validator:AddRule( {
	Matches = function( self, Config )
		return Config.Rates.SendRate > Config.Rates.MoveRate
	end,
	Fix = function( self, Config )
		Config.Rates.SendRate = Config.Rates.MoveRate
		Notify( "Send rate cannot be more than move rate. Clamping to move rate." )
	end
} )
Validator:AddRule( {
	Matches = function( self, Config )
		local MinInterp = 2 / Config.Rates.SendRate * 1000

		if Config.Rates.Interp < MinInterp then
			Config.Rates.Interp = MinInterp
			Notify( StringFormat( "Interp cannot be less than %.2fms, clamping...",
				MinInterp ) )
			return true
		end

		return false
	end
} )
RatesModule.ConfigValidator = Validator

function RatesModule:Initialise()
	self:CheckRateValues()
end

local function Transform( Rate, Value )
	return Rate.Transformer and Rate.Transformer( Value ) or Value
end

function RatesModule:CheckRateValues()
	if not self.Config.Rates.ApplyRates then return end

	for i = 1, #Rates do
		local Rate = Rates[ i ]
		local ConfigValue = self.Config.Rates[ Rate.Key ]

		-- Only skip applying values where we can get the current value. Any rates that
		-- have no getter should always be applied in case they've been changed elsewhere.
		local Default = IsType( Rate.Default, "function" ) and Rate.Default() or nil
		if ConfigValue ~= Default then
			local ActualValue = Transform( Rate, ConfigValue )
			local Command = IsType( Rate.Command, "function" ) and Rate.Command( ActualValue )
				or StringFormat( Rate.Command, ActualValue )

			Shared.ConsoleCommand( Command )
		end

		if Rate.WarnIfBelow and ConfigValue < Rate.WarnIfBelow then
			Notify( StringFormat( "WARNING: %s is below the default of %s", Rate.Key, Rate.WarnIfBelow ) )
		end
	end
end

Plugin:AddModule( RatesModule )
