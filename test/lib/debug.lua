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
