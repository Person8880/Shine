--[[
	Tests for colour helpers.
]]

local UnitTest = Shine.UnitTest

Shine.GUI = Shine.GUI or {}
local SGUI = Shine.GUI

Script.Load( "lua/shine/lib/colour.lua" )

UnitTest:Test( "IsColour - Returns true for a colour object", function( Assert )
	Assert.True( "Should return true for a colour object", SGUI.IsColour( Colour( 1, 1, 1 ) ) )
end )

UnitTest:Test( "IsColour - Returns false for a different cdata type", function( Assert )
	Assert.False( "Should return false for a vector object", SGUI.IsColour( Vector( 1, 1, 1 ) ) )
end )

UnitTest:Test( "IsColour - Returns false for a non-cdata type", function( Assert )
	Assert.False( "Should return false for a non-cdata object", SGUI.IsColour( "not a colour" ) )
end )

local function AssertColoursEqual( Assert, A, B )
	Assert.Equals( "Red values must match", A.r, B.r )
	Assert.Equals( "Green values must match", A.g, B.g )
	Assert.Equals( "Blue values must match", A.b, B.b )
	Assert.Equals( "Alpha values must match", A.a, B.a )
end

UnitTest:Test( "ColourSum should add values component-wise", function( Assert )
	local Red = Colour( 1, 0, 0 )
	local Green = Colour( 0, 1, 0 )

	AssertColoursEqual( Assert, Colour( 1, 1, 0, 2 ), SGUI.ColourSum( Red, Green ) )
end )

UnitTest:Test( "ColourSub should subtract values component-wise", function( Assert )
	local White = Colour( 1, 1, 1 )
	local Red = Colour( 1, 0, 0 )

	AssertColoursEqual( Assert, Colour( 0, 1, 1, 0 ), SGUI.ColourSub( White, Red ) )
end )

UnitTest:Test( "CopyColour should return an exact copy", function( Assert )
	local Orange = Colour( 1, 0.4, 0 )
	local Copy = SGUI.CopyColour( Orange )

	AssertColoursEqual( Assert, Orange, Copy )
	Assert.NotSame( "Should have returned a new colour object", Orange, Copy )
end )

UnitTest:Test( "ColourLerp should interpolate linearly", function( Assert )
	local ColourToLerp = Colour( 0, 0, 0 )
	local Start = Colour( 0, 0, 0 )
	local Diff = Colour( 1, 0.5, 0.25, 0 )

	SGUI.ColourLerp( ColourToLerp, Start, 0.5, Diff )

	AssertColoursEqual( Assert, Colour( 0.5, 0.25, 0.125 ), ColourToLerp )
end )

UnitTest:Test( "ColourWithAlpha should return a copy with the given alpha", function( Assert )
	local Orange = Colour( 1, 0.4, 0 )
	local Copy = SGUI.ColourWithAlpha( Orange, 0.5 )

	AssertColoursEqual( Assert, Colour( 1, 0.4, 0, 0.5 ), Copy )
	Assert:NotSame( Orange, Copy )
end )

UnitTest:Test( "RGBToHSV should convert colours as expected", function( Assert )
	local H, S, V = SGUI.RGBToHSV( 1, 0, 0 )

	Assert:Equals( 0, H )
	Assert:Equals( 1, S )
	Assert:Equals( 1, V )

	H, S, V = SGUI.RGBToHSV( 0, 1, 0 )

	Assert:Equals( 120 / 360, H )
	Assert:Equals( 1, S )
	Assert:Equals( 1, V )

	H, S, V = SGUI.RGBToHSV( 0, 0, 1 )

	Assert:Equals( 240 / 360, H )
	Assert:Equals( 1, S )
	Assert:Equals( 1, V )

	H, S, V = SGUI.RGBToHSV( 0.1, 0.1, 0.1 )

	Assert:Equals( 0, H )
	Assert:Equals( 0, S )
	Assert:Equals( 0.1, V )
end )

UnitTest:Test( "HSVToRGB should convert colours as expected", function( Assert )
	local R, G, B = SGUI.HSVToRGB( 0, 1, 1 )

	Assert:Equals( 1, R )
	Assert:Equals( 0, G )
	Assert:Equals( 0, B )

	R, G, B = SGUI.HSVToRGB( 120 / 360, 1, 1 )

	Assert:Equals( 0, R )
	Assert:Equals( 1, G )
	Assert:Equals( 0, B )

	R, G, B = SGUI.HSVToRGB( 240 / 360, 1, 1 )

	Assert:Equals( 0, R )
	Assert:Equals( 0, G )
	Assert:Equals( 1, B )

	R, G, B = SGUI.HSVToRGB( 0, 0, 0.1 )

	Assert:Equals( 0.1, R )
	Assert:Equals( 0.1, G )
	Assert:Equals( 0.1, B )
end )

UnitTest:Test( "SaturateColour should apply saturation multiplier as expected", function( Assert )
	local Orange = Colour( 1, 0.4, 0 )
	local H1, S1, V1 = SGUI.RGBToHSV( Orange.r, Orange.g, Orange.b )

	local DesaturatedOrange = SGUI.SaturateColour( Orange, 0.5 )

	local H2, S2, V2 = SGUI.RGBToHSV( DesaturatedOrange.r, DesaturatedOrange.g, DesaturatedOrange.b )

	Assert.EqualsWithTolerance( "Hue should be unchanged", H1, H2 )
	Assert.EqualsWithTolerance( "Saturation should be havled", S1 * 0.5, S2 )
	Assert.EqualsWithTolerance( "Value should be unchanged", V1, V2 )
end )
