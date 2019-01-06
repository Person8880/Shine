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

	local Enum = table.AsEnum{
		"A", "B"
	}
	Validator:AddFieldRule( "ListOfEnums", Validator.Each( Validator.InEnum( Enum ) ) )
	Validator:AddFieldRules( { "SingleEnum", "AnotherEnum" }, Validator.InEnum( Enum, Enum.B ) )
	Validator:AddFieldRule( "SingleEnum", Validator.IsType( "string", 1 ) )

	Validator:AddFieldRule( "ListOfTables", Validator.Each(
		Validator.ValidateField( "ShouldBeNumber", Validator.IsType( "number", 1 ) )
	) )
	Validator:AddFieldRule( "ListOfTables", Validator.Each(
		Validator.ValidateField( "CanBeNilOrNumber", Validator.IsAnyType( { "number", "nil" }, 0 ) )
	) )

	local Config = {
		TooSmallNumber = 5,
		BigEnoughNumber = 11,
		Nested = {
			Field = 2
		},
		ListOfEnums = { "A", "C", "b" },
		SingleEnum = "a",
		AnotherEnum = "C",
		ListOfTables = {
			{ ShouldBeNumber = 0 },
			{ ShouldBeNumber = "1", CanBeNilOrNumber = true }
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
	-- Should remove the invalid enum, maintaining the array structure.
	Assert:ArrayEquals( { "A", "B" }, Config.ListOfEnums )
	-- Should upper-case the valid string enum.
	Assert:Equals( "A", Config.SingleEnum )
	-- Should replace the invalid enum.
	Assert:Equals( "B", Config.AnotherEnum )

	Assert:DeepEquals( {
		{ ShouldBeNumber = 0 },
		{ ShouldBeNumber = 1, CanBeNilOrNumber = 0 }
	}, Config.ListOfTables )
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

UnitTest:Test( "VerifyConfig updates when required", function( Assert )
	local DefaultConfig = {
		A = true,
		B = true,
		C = {
			A = true,
			B = true,
			C = { 1, 2, 3 }
		},
		D = Shine.IgnoreWhenChecking( {
			A = true
		} )
	}

	local ProvidedConfig = {
		A = true,
		C = {
			B = true,
			D = "cake",
			C = { 1 }
		},
		D = {
			B = true
		},
		E = "cake",
		__Version = "1.0"
	}

	local Updated = Shine.VerifyConfig( ProvidedConfig, DefaultConfig, { __Version = true } )
	Assert.True( "Config should have been updated", Updated )
	Assert.Equals( "Should have added missing top-level key", true, ProvidedConfig.B )
	Assert.Equals( "Should have added missing sub-level key", true, ProvidedConfig.C.A )
	Assert.ArrayEquals( "Should have left array alone", { 1 }, ProvidedConfig.C.C )
	Assert.TableEquals( "Should have left ignored table alone", { B = true }, ProvidedConfig.D )
	Assert.Equals( "Should have removed obselete top-level key", nil, ProvidedConfig.E )
	Assert.Equals( "Should have removed obselete sub-level key", nil, ProvidedConfig.C.D )
	Assert.Equals( "Should have left reserved key alone", "1.0", ProvidedConfig.__Version )
end )

UnitTest:Test( "VerifyConfig does nothing when config matches", function( Assert )
	local DefaultConfig = {
		A = true,
		B = true,
		C = {
			A = true,
			B = true,
			C = { 1, 2, 3 }
		},
		D = Shine.IgnoreWhenChecking( {
			A = true
		} )
	}
	local ProvidedConfig = {
		A = true,
		B = true,
		C = {
			A = true,
			B = true,
			C = { 1 }
		},
		D = {
			B = true
		},
		__Version = "1.0"
	}
	local ExpectedConfig = table.Copy( ProvidedConfig )

	local Updated = Shine.VerifyConfig( ProvidedConfig, DefaultConfig, { __Version = true } )
	Assert.False( "Config should not have been updated", Updated )
	Assert.DeepEquals( "Config values should remain unchanged", ExpectedConfig, ProvidedConfig )
end )

UnitTest:Test( "Migrator", function( Assert )
	local Migrator = Shine.Migrator()
		:RenameField( "A", "B" )
		:UseEnum( "Mode", { "Mode1", "Mode2", "Mode3" } )
		:ApplyAction( function( Config )
			Config.ActionApplied = true
		end )

	local Config = {
		A = "Value for A",
		Mode = 2
	}
	Assert.DeepEquals( "Migrator should apply actions as expected", {
		B = "Value for A",
		Mode = "Mode2",
		ActionApplied = true
	}, Migrator( Config ) )
end )
