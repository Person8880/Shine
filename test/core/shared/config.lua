--[[
	Config tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Validator", function( Assert )
	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function() return true end,
		Fix = function( self, Config )
			Config.Fixed = true
		end
	} )
	Validator:AddRule( {
		Matches = function() return false end,
		Fix = function( self, Config )
			Config.Broken = true
		end
	} )
	Validator:AddRule( {
		Matches = function() return true end,
		Fix = function( self, Config )
			Config.ReallyFixed = true
		end
	} )
	Validator:AddFieldRule( "TooSmallNumber", Validator.Min( 10 ) )
	Validator:AddFieldRule( "BigEnoughNumber", Validator.Min( 10 ) )
	Validator:AddFieldRule( "Nested.Field", Validator.Clamp( 0, 1 ) )
	Validator:AddFieldRule( "Nested.NonExistent.Field", Validator.Min( 5 ) )

	local Config = {
		TooSmallNumber = 5,
		BigEnoughNumber = 11,
		Nested = {
			Field = 2
		}
	}
	Assert:True( Validator:Validate( Config ) )
	Assert:True( Config.Fixed )
	Assert:Nil( Config.Broken )
	Assert:True( Config.ReallyFixed )
	-- Should ensure minimum value of 10
	Assert:Equals( 10, Config.TooSmallNumber )
	-- Should ignore as already larger than minimum of 10
	Assert:Equals( 11, Config.BigEnoughNumber )
	-- Should clamp into [0, 1] range
	Assert:Equals( 1, Config.Nested.Field )
	-- Should create with the min value
	Assert:Equals( 5, Config.Nested.NonExistent.Field )
end )

UnitTest:Test( "TypeCheckConfig", function( Assert )
	local Config = {
		Blah = true,
		Bleh = "nope"
	}

	local DefaultConfig = {
		Blah = true,
		Bleh = true
	}

	Assert:True( Shine.TypeCheckConfig( "test", Config, DefaultConfig ) )
	Assert:True( Config.Bleh )

	DefaultConfig.SubConfig = {
		Test = "String"
	}
	Config.SubConfig = {
		Test = true
	}

	Assert:True( Shine.TypeCheckConfig( "test", Config, DefaultConfig, true ) )
	Assert:Equals( "String", Config.SubConfig.Test )
end )
