--[[
	Element to set the current colour for rich text.
]]

local StringFormat = string.format

local BaseElement = require "shine/lib/gui/richtext/elements/base"
local Colour = Shine.TypeDef( BaseElement )

function Colour:Init( Value )
	self.Value = Value
	return self
end

function Colour:Split()
	-- Element is not splittable.
end

function Colour:GetWidth()
	return 0, 0
end

function Colour:MakeElement( Context )
	Context.CurrentColour = self.Value
end

function Colour:__tostring()
	return StringFormat( "Colour (%s, %s, %s, %s)", self.Value.r, self.Value.g, self.Value.b, self.Value.a )
end

return Colour
