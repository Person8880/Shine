--[[
	Useful colour functions.
]]

local SGUI = Shine.GUI

Colour = Color --I'm British, I can't stand writing Color.
local Colour = Colour

local getmetatable = getmetatable
local ColourMetatable = getmetatable( Colour( 0, 0, 0 ) )

--[[
	Determines if the passed in object is a colour.
]]
function SGUI.IsColour( Object )
	-- Apparently vectors and colours share the same metatable...
	return getmetatable( Object ) == ColourMetatable and Object.r
end

--[[
	Returns the sum of two colours.
	Note that the elements of the returned colour may be more than 255.
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
function SGUI.ColourLerp( self, Start, Progress, Diff )
	self.r = Start.r + Progress * Diff.r
	self.g = Start.g + Progress * Diff.g
	self.b = Start.b + Progress * Diff.b
	self.a = Start.a + Progress * Diff.a
end
