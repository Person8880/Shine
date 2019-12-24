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
	Validator:AddFieldRule( "TooSmallNumber", Validator.IsType( "number", 10 ), Validator.Min( 10 ) )
	Validator:AddFieldRule( "BigEnoughNumber", Validator.IsType( "number", 10 ), Validator.Min( 10 ) )
	Validator:AddFieldRule( "Nested.Field", Validator.Clamp( 0, 1 ) )
	Validator:AddFieldRule( "Nested.NonExistent.Field", Validator.Min( 5 ) )

	local Enum = table.AsEnum{
		"A", "B"
	}
	Validator:AddFieldRule( "ListOfEnums", Validator.Each( Validator.InEnum( Enum ) ) )
	Validator:AddFieldRules( { "SingleEnum", "AnotherEnum" }, Validator.InEnum( Enum, Enum.B ) )
	Validator:AddFieldRule( "SingleEnum", Validator.IsType( "string", 1 ) )

	Validator:AddFieldRule( "ListOfTables", Validator.AllValuesSatisfy(
		Validator.ValidateField( "ShouldBeNumber", Validator.IsType( "number", 1 ) ),
		Validator.ValidateField( "CanBeNilOrNumber", Validator.IsAnyType( { "number", "nil" }, 5 ) ),
		Validator.ValidateField( "CanBeNilOrNumber", Validator.IfType( "number", Validator.Min( 5 ) ) ),
		Validator.ValidateField( "Enum", Validator.InEnum( Enum, Enum.A ) ),
		Validator.ValidateField( "SecondEnum", Validator.InEnum( Enum ), { DeleteIfFieldInvalid = true } ),
		Validator.ValidateField( "ThirdEnum", Validator.InEnum( Enum ) )
	) )

	Validator:CheckTypesAgainstDefault( "TypeCheckedChild", {
		A = false,
		B = "cake",
		C = 123,
		D = {}
	} )

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
			{ ShouldBeNumber = 0, Enum = "b", SecondEnum = "A", ThirdEnum = 123 },
			{ ShouldBeNumber = "1", CanBeNilOrNumber = true, SecondEnum = "B", ThirdEnum = "a" },
			-- This should be deleted due to the DeleteIfFieldInvalid flag.
			{ SecondEnum = "C" }
		},
		TypeCheckedChild = {
			A = true,
			B = "cake",
			C = 123,
			D = 456
		}
	}
	Assert:True( Validator:Validate( Config ) )

	Assert:DeepEquals( {
		Fixed = true,
		ReallyFixed = true,
		-- Should ensure minimum value of 10
		TooSmallNumber = 10,
		-- Should ignore as already larger than minimum of 10
		BigEnoughNumber = 11,
		Nested = {
			-- Should clamp into [0, 1] range
			Field = 1,
			NonExistent = {
				-- Should create with the min value
				Field = 5
			}
		},
		-- Should remove the invalid enum, maintaining the array structure.
		ListOfEnums = { "A", "B" },
		-- Should upper-case the valid string enum.
		SingleEnum = "A",
		-- Should replace the invalid enum.
		AnotherEnum = "B",
		ListOfTables = {
			-- Should correct each entry in the list.
			{ ShouldBeNumber = 0, Enum = "B", SecondEnum = "A" },
			{ ShouldBeNumber = 1, CanBeNilOrNumber = 5, Enum = "A", SecondEnum = "B", ThirdEnum = "A" }
		},
		TypeCheckedChild = {
			-- Should ensure all fields have the same type as the default config.
			A = true,
			B = "cake",
			C = 123,
			D = {}
		}
	}, Config )
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
		:AddField( "D", "Value for D" )
		:AddField( { "Child2", "Value" }, false )
		:RenameField( "A", "B" )
		:RenameField( "C", { "Child", "C" } )
		:RenameField( { "Nested", "Value" }, { "Child", "Value" } )
		:CopyField( "Child", "CopiedChild" )
		:RemoveField( "Nested" )
		:UseEnum( "Mode", { "Mode1", "Mode2", "Mode3" } )
		:RenameEnums( {
			"OldEnum1",
			"OldEnum2"
		}, "OLD_VALUE1", "NEW_VALUE1" )
		:ApplyAction( function( Config )
			Config.ActionApplied = true
		end )

	local Config = {
		A = "Value for A",
		C = "Value for C",
		Mode = 2,
		Nested = {
			Value = true
		},
		OldEnum1 = "OLD_VALUE1",
		OldEnum2 = "OLD_VALUE2"
	}
	Assert.DeepEquals( "Migrator should apply actions as expected", {
		B = "Value for A",
		Child = {
			C = "Value for C",
			Value = true
		},
		CopiedChild = {
			C = "Value for C",
			Value = true
		},
		Child2 = {
			Value = false
		},
		D = "Value for D",
		Mode = "Mode2",
		OldEnum1 = "NEW_VALUE1",
		OldEnum2 = "OLD_VALUE2",
		ActionApplied = true
	}, Migrator( Config ) )
end )
