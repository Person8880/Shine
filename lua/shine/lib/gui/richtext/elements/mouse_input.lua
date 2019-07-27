--[[
	Element to add mouse input to rich text.
]]

local StringFormat = string.format

local BaseElement = require "shine/lib/gui/richtext/elements/base"
local MouseInput = Shine.TypeDef( BaseElement )

function MouseInput:Init( Params )
	self.DoClick = Params.DoClick
	self.DoRightClick = Params.DoRightClick
	return self
end

function MouseInput:Split()
	-- Element is not splittable.
end

function MouseInput:GetWidth()
	return 0, 0
end

function MouseInput:MakeElement( Context )
	Context.DoClick = self.DoClick
	Context.DoRightClick = self.DoRightClick
end

function MouseInput:__tostring()
	return StringFormat( "MouseInput (DoClick = %s, DoRightClick = %s)", self.DoClick, self.DoRightClick )
end

return MouseInput
