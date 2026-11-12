--[[
	Server rates configuration.
]]

local Plugin = ...

local IsType = Shine.IsType
local Notify = Shared.Message
local pairs = pairs
local StringFormat = string.format

local StockRates = { BWLimit = 50, Interp = 100, MoveRate = 26, SendRate = 20, TickRate = 30 }
-- Interp 0 lets the engine size interp from the send and move rates.
local BetaRates = { BWLimit = 100, Interp = 0, MoveRate = 60, SendRate = 30, TickRate = 60 }

-- The higher rates rely on beta engine server work.
local IsBetaEngine = Shared.GetBuildNumber() >= 345
local DefaultRates = IsBetaEngine and BetaRates or StockRates

local RatesModule = {}
RatesModule.DefaultConfig = {
	Rates = {
		-- Whether to enforce these rate settings or leave the defaults as-is.
		ApplyRates = true,
		-- Stops a config that still holds the stock rates being moved to the beta engine's defaults. Set once that
		-- happens, or when an admin sets a rate.
		KeepSavedRates = false,
		BWLimit = DefaultRates.BWLimit,
		Interp = DefaultRates.Interp,
		MoveRate = DefaultRates.MoveRate,
		SendRate = DefaultRates.SendRate,
		TickRate = DefaultRates.TickRate
	}
}

local Rates = {
	{
		Key = "MoveRate",
		Min = 5,
		Integer = true,
		Default = DefaultRates.MoveRate,
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
		Default = DefaultRates.Interp,
		Command = function( Value )
			if Value == 0 then return "interp auto" end
			return StringFormat( "interp %s", Value * 0.001 )
		end
	},
	{
		Key = "BWLimit",
		Min = 5,
		Transformer = function( Value ) return Value * 1024 end,
		Default = function() return Server.GetBwLimit() / 1024 end,
		Command = "bwlimit %s"
	}
}

local Validator = Shine.Validator()
Validator:AddFieldRule( "Rates.ApplyRates", Validator.IsType( "boolean", true ) )
Validator:AddFieldRule( "Rates.KeepSavedRates", Validator.IsType( "boolean", false ) )
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

		if not ( Config.Rates.Interp == 0 and IsBetaEngine ) and Config.Rates.Interp < MinInterp then
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

function RatesModule:IsInterpAutoSupported()
	return IsBetaEngine
end

-- Runs on every load rather than as a config migration, so a server that moves from the stock engine to a beta build
-- later still gets the new defaults.
function RatesModule:UpgradeStockRates()
	local ConfigRates = self.Config.Rates
	if not IsBetaEngine or ConfigRates.KeepSavedRates then return end

	for Key, Value in pairs( StockRates ) do
		if ConfigRates[ Key ] ~= Value then return end
	end

	for Key, Value in pairs( BetaRates ) do
		ConfigRates[ Key ] = Value
	end
	ConfigRates.KeepSavedRates = true
	self:SaveConfig( true )

	Notify( "Saved rates were the stock defaults, replaced with this engine's defaults: tick rate 60, move rate 60, "..
		"send rate 30, interp auto, bandwidth limit 100 KB/s." )
end

function RatesModule:CheckRateValues()
	if not self.Config.Rates.ApplyRates then return end

	self:UpgradeStockRates()

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
	end

	-- A snapshot larger than BWLimit / SendRate is held back until it clears, which players see as warping.
	local MinBWLimit = 2 * self.Config.Rates.SendRate
	if self.Config.Rates.BWLimit < MinBWLimit then
		Notify( StringFormat( "WARNING: BWLimit %s KB/s leaves less than 2 KB per snapshot at send rate %s. Use at least %s.",
			self.Config.Rates.BWLimit, self.Config.Rates.SendRate, MinBWLimit ) )
	end
end

Plugin:AddModule( RatesModule )
