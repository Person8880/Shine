--[[
	Debug library tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "JoinUpValues", function( Assert )
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

UnitTest:Test( "TypeCheck", function( Assert )
	local Value = 1
	local Success, Err = pcall( Shine.TypeCheck, Value, "string", 1, "Test", 0 )

	Assert:False( Success )
	Assert:Equals( "Bad argument #1 to 'Test' (string expected, got number)", Err )

	Success, Err = pcall( Shine.TypeCheck, Value, "number", 1, "Test", 0 )
	Assert:True( Success )

	Success, Err = pcall( Shine.TypeCheck, Value, { "number", "string" }, 1, "Test", 0 )
	Assert:True( Success )

	Success, Err = pcall( Shine.TypeCheck, Value, { "string", "table" }, 1, "Test", 0 )
	Assert:False( Success )
	Assert:Equals( "Bad argument #1 to 'Test' (string or table expected, got number)", Err )
end )
