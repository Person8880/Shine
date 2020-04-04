--[[
	Useful colour functions.
]]

local SGUI = Shine.GUI

Colour = Color --I'm British, I can't stand writing Color.
local Colour = Colour

local Floor = math.floor
local Max = math.max
local Min = math.min
local type = type

local IsColour
do
	local FFILoaded, FFI = pcall( require, "ffi" )
	if FFILoaded and FFI and FFI.istype then
		local Success, PassedCheck = pcall( FFI.istype, "Color", Colour( 1, 1, 1 ) )
		if Success and PassedCheck then
			local IsType = FFI.istype
			IsColour = function( Colour ) return IsType( "Color", Colour ) end
		end
	end

	if not IsColour then
		-- This is more risky as cdata can be anything.
		IsColour = function( Colour ) return Colour:isa( "Color" ) end
	end
end

--[[
	Determines if the passed in object is a colour.
]]
function SGUI.IsColour( Object )
	return type( Object ) == "cdata" and IsColour( Object )
end

--[[
	Returns the sum of two colours.
	Note that the elements of the returned colour may be more than 1.
]]
function SGUI.ColourSum( Col1, Col2 )
	return Colour( Col1.r + Col2.r, Col1.g + Col2.g, Col1.b + Col2.b, Col1.a + Col2.a )
end

--[[
	Returns the first colour minus the second colour.
	Note that the elements of the returned may be negative.
]]
function SGUI.ColourSub( Col1, Col2 )
	return Colour( Col1.r - Col2.r, Col1.g - Col2.g, Col1.b - Col2.b, Col1.a - Col2.a )
end

--[[
	Returns a copy of the colour object.
]]
function SGUI.CopyColour( Col )
	return Colour( Col.r, Col.g, Col.b, Col.a )
end

--[[
	Lerps the current colour from the start value with the given difference and progress.
	Edits the current colour.
]]
function SGUI.ColourLerp( ColourToLerp, Start, Progress, Diff )
	ColourToLerp.r = Start.r + Progress * Diff.r
	ColourToLerp.g = Start.g + Progress * Diff.g
	ColourToLerp.b = Start.b + Progress * Diff.b
	ColourToLerp.a = Start.a + Progress * Diff.a
end

--[[
	Copies the given colour, applying the given alpha.
]]
function SGUI.ColourWithAlpha( ColourToCopy, Alpha )
	return Colour( ColourToCopy.r, ColourToCopy.g, ColourToCopy.b, Alpha )
end

local function RGBToHSV( R, G, B )
	local MaxValue = Max( R, G, B )
	local MinValue = Min( R, G, B )
	local Diff = MaxValue - MinValue

	local Hue
	if MaxValue == MinValue then
		Hue = 0
	elseif MaxValue == R then
		Hue = 60 * ( G - B ) / Diff
	elseif MaxValue == G then
		Hue = 60 * ( 2 + ( B - R ) / Diff )
	else
		Hue = 60 * ( 4 + ( R - G ) / Diff )
	end

	if Hue < 0 then
		Hue = Hue + 360
	end

	local Saturation
	if Max == 0 then
		Saturation = 0
	else
		Saturation = Diff / MaxValue
	end

	return Hue / 360, Saturation, MaxValue
end
SGUI.RGBToHSV = RGBToHSV

local function HSVToRGB( H, S, V )
	local R, G, B

	local i = Floor( H * 6 )
	local f = H * 6 - i
	local p = V * ( 1 - S )
	local q = V * ( 1 - f * S )
	local t = V * ( 1 - ( 1 - f ) * S )

	i = i % 6

	if i == 0 then
		R, G, B = V, t, p
	elseif i == 1 then
		R, G, B = q, V, p
	elseif i == 2 then
		R, G, B = p, V, t
	elseif i == 3 then
		R, G, B = p, q, V
	elseif i == 4 then
		R, G, B = t, p, V
	elseif i == 5 then
		R, G, B = V, p, q
	end

	return R, G, B
end
SGUI.HSVToRGB = HSVToRGB

--[[
	Applies the given multiplier to the colour's current saturation value (in HSV space).
	Saturation cannot exceed 100%.
]]
function SGUI.SaturateColour( ColourToSaturate, Multiplier )
	local Hue, Saturation, Value = RGBToHSV( ColourToSaturate.r, ColourToSaturate.g, ColourToSaturate.b )
	return Colour( HSVToRGB( Hue, Min( Saturation * Multiplier, 1 ), Value ) )
end
