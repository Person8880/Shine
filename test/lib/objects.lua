--[[
	Object definition testing.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "TypeDef", function( Assert )
	local Type = Shine.TypeDef()

	Assert:IsType( getmetatable( Type ).__call, "function" )
	Assert:Nil( getmetatable( Type ).__index )

	local InitCalled
	function Type:Init( Value )
		Assert:True( Value )
		InitCalled = true
		return self
	end

	local Instance = Type( true )
	Assert:True( InitCalled )
	Assert:Equals( getmetatable( Instance ), Type )
end )

UnitTest:Test( "TypeDef inheritance", function( Assert )
	local Base = Shine.TypeDef()
	local Child = Shine.TypeDef( Base )

	Assert:Equals( Base, getmetatable( Child ).__index )

	local InitCalled
	function Base:Init( Value )
		Assert:False( Value )
		InitCalled = true
		return self
	end

	local Instance = Child( false )
	Assert:True( InitCalled )
end )

UnitTest:Test( "Implements - Returns true when the value implements the given metatable", function( Assert )
	local Base = Shine.TypeDef()
	Base.Init = function( self ) return self end

	local Child = Shine.TypeDef( Base )
	local Value = Child()

	Assert.True( "Object should implement its metatable", Shine.Implements( Value, Child ) )
	Assert.True( "Object should implement the parent metatable", Shine.Implements( Value, Base ) )
end )

UnitTest:Test( "Implements - Returns false when the value does not implement the given metatable", function( Assert )
	local Type1 = Shine.TypeDef()
	Type1.Init = function( self ) return self end

	local Type2 = Shine.TypeDef()
	local Value = Type1()

	Assert.False( "Object should not implement the given metatable", Shine.Implements( Value, Type2 ) )
end )
