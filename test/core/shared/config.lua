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

	local Config = {}
	Assert:True( Validator:Validate( Config ) )
	Assert:True( Config.Fixed )
	Assert:Nil( Config.Broken )
	Assert:True( Config.ReallyFixed )
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
