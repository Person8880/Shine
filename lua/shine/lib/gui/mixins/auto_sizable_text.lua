--[[
	Provides auto-sizing logic based on element text.
]]

local AutoSizeText = {}
local AxisSizeHandlers = {
	function( self )
		return self:GetTextWidth()
	end,
	function( self )
		return self:GetTextHeight()
	end
}

function AutoSizeText:GetContentSizeForAxis( Axis )
	return AxisSizeHandlers[ Axis ]( self )
end

function AutoSizeText:GetTextWidth( Text )
	if not self.Label then return 0 end

	local Scale = self.TextScale
	Scale = Scale and Scale.x or 1

	return self.Label:GetTextWidth( Text or self.Label:GetText() ) * Scale
end

function AutoSizeText:GetTextHeight( Text )
	if not self.Label then return 0 end

	local Scale = self.TextScale
	Scale = Scale and Scale.y or 1

	return self.Label:GetTextHeight( Text or self.Label:GetText() ) * Scale
end

Shine.GUI:RegisterMixin( "AutoSizeText", AutoSizeText )
