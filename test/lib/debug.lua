--[[
	Debug library tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "JoinUpValues - Non recursive", function( Assert )
	local Up1, Up2
	local function OriginalFunc()
		Up1 = 1
		Up2 = 2
	end

	local Up3, Up4
	local function TargetFunc()
		Up3 = 3
		Up4 = 4
	end

	Shine.JoinUpValues( OriginalFunc, TargetFunc, {
		Up1 = "Up3",
		Up2 = "Up4"
	} )

	TargetFunc()

	Assert:Equals( 3, Up1 )
	Assert:Equals( 4, Up2 )
end )

UnitTest:Test( "JoinUpValues - Recursive with predicate", function( Assert )
	local Up1, Up2
	local function OriginalFunc()
		Up1 = 1
		Up2 = 2
	end

	local function WrappedFunc()
		return OriginalFunc()
	end

	local Up3, Up4
	local function TargetFunc()
		Up3 = 3
		Up4 = 4
	end

	Shine.JoinUpValues( WrappedFunc, TargetFunc, {
		Up1 = {
			Name = "Up3",
			Predicate = function( Func, Name, Value )
				Assert.Equals( "Should pass the predicate the original function", OriginalFunc, Func )
				Assert.Equals( "Should pass in the expected name", "Up1", Name )
				Assert.Nil( "Should pass in the current value", Value )
				return false
			end
		},
		Up2 = "Up4"
	}, true )

	TargetFunc()

	-- Up1 doesn't pass the predicate so should not be joined.
	Assert.Nil( "First upvalue should not have been joined", Up1 )
	Assert.Equals( "Second upvalue should have been joined", 4, Up2 )
end )

UnitTest:Test( "UpValuePredicates.DefinedInFile", function( Assert )
	local function TestFunction() end
	local Predicate = Shine.UpValuePredicates.DefinedInFile( "test/lib/debug.lua" )
	Assert.True( "Should detect functions defined in the given file", Predicate( TestFunction ) )
	Assert.False(
		"Should detect functions not defined in the given file",
		Predicate( Shine.UpValuePredicates.DefinedInFile )
	)
end )

UnitTest:Test( "TypeCheck", function( Assert )
	local Value = 1
	local Success, Err = pcall( Shine.TypeCheck, Value, "string", 1, "Test", 0 )

	Assert:False( Success )
	Assert:Equals( "Bad argument #1 to 'Test' (string expected, got number)", Err )

	Success, Err = pcall( Shine.TypeCheck, Value, "number", 1, "Test", 0 )
	Assert:True( Success )
	Assert.Equals( "Return value should be the passed in value", Value, Err )

	Success, Err = pcall( Shine.TypeCheck, Value, { "number", "string" }, 1, "Test", 0 )
	Assert:True( Success )
	Assert.Equals( "Return value should be the passed in value", Value, Err )

	Success, Err = pcall( Shine.TypeCheck, Value, { "string", "table" }, 1, "Test", 0 )
	Assert:False( Success )
	Assert:Equals( "Bad argument #1 to 'Test' (string or table expected, got number)", Err )
end )

UnitTest:Test( "TypeCheckField", function( Assert )
	local Table = {
		Field = 1
	}

	local Success, Err = pcall( Shine.TypeCheckField, Table, "Field", "string", "Test", 0 )

	Assert:False( Success )
	Assert:Equals( "Bad value for field 'Field' on Test (string expected, got number)", Err )

	Success, Err = pcall( Shine.TypeCheckField, Table, "Field", "number", "Test", 0 )
	Assert:True( Success )
	Assert.Equals( "Return value should be the passed in field value", Table.Field, Err )

	Success, Err = pcall( Shine.TypeCheckField, Table, "Field", { "number", "string" }, "Test", 0 )
	Assert:True( Success )
	Assert.Equals( "Return value should be the passed in field value", Table.Field, Err )

	Success, Err = pcall( Shine.TypeCheckField, Table, "Field", { "string", "table" }, "Test", 0 )
	Assert:False( Success )
	Assert:Equals( "Bad value for field 'Field' on Test (string or table expected, got number)", Err )
end )

UnitTest:Test( "GetUpValueAccessor", function( Assert )
	local TargetUpValue = {}
	local function FuncReferencingTarget()
		return TargetUpValue
	end

	local Getter, Setter = Shine.GetUpValueAccessor( FuncReferencingTarget, "TargetUpValue" )
	Assert.Equals( "Getter didn't return upvalue", Getter(), TargetUpValue )

	TargetUpValue = {}
	Assert.Equals( "Getter didn't return upvalue after re-assignment", Getter(), TargetUpValue )

	Setter( 123 )
	Assert.Equals( "Setter didn't update the upvalue", 123, TargetUpValue )
	Assert.Equals( "Getter doesn't reflect state after calling setter", 123, Getter() )
end )

UnitTest:Test( "GetLocals - omits var-args when none provided", function( Assert )
	local NilMarker = "nil"

	local function FunctionWithLocals()
		local A = 1
		local B = "test"
		local C = {
			Values = true
		}
		local D

		local LocalValues = Shine.GetLocals( 1, NilMarker )
		return LocalValues
	end

	local Values = FunctionWithLocals()
	Assert:DeepEquals( {
		A = 1,
		B = "test",
		C = {
			Values = true
		},
		D = NilMarker,
		NilMarker = NilMarker
	}, Values )
end )

UnitTest:Test( "GetLocals - includes var-args when provided", function( Assert )
	local function FunctionWithLocals( ... )
		local A = 1
		local B = "test"
		local C = {
			Values = true
		}

		local LocalValues = Shine.GetLocals( 1 )
		return LocalValues
	end

	local Values = FunctionWithLocals( "var", "args", "here", 1, 2, 3 )
	Assert:DeepEquals( {
		A = 1,
		B = "test",
		C = {
			Values = true
		},
		[ "select( 1, ... )" ] = "var",
		[ "select( 2, ... )" ] = "args",
		[ "select( 3, ... )" ] = "here",
		[ "select( 4, ... )" ] = 1,
		[ "select( 5, ... )" ] = 2,
		[ "select( 6, ... )" ] = 3,
		[ "select( \"#\", ... )" ] = 6
	}, Values )

	Values = FunctionWithLocals()
	Assert:DeepEquals( {
		A = 1,
		B = "test",
		C = {
			Values = true
		},
		[ "select( \"#\", ... )" ] = 0
	}, Values )
end )
