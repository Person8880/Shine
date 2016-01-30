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
