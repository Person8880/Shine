--[[
	Provides auto-sizing logic based on element text.
]]

local AutoSizeText = {}
local AxisSizeHandlers = {
	function( self )
		return self:GetCachedTextWidth()
	end,
	function( self )
		return self:GetCachedTextHeight()
	end
}

function AutoSizeText:GetContentSizeForAxis( Axis )
	return AxisSizeHandlers[ Axis ]( self )
end

local function GetTextWidth( Label, Scale, Text )
	Scale = Scale and Scale.x or 1
	return Label:GetTextWidth( Text ) * Scale
end

function AutoSizeText:GetCachedTextWidth()
	if self.CachedTextWidth then
		return self.CachedTextWidth
	end

	self.CachedTextWidth = GetTextWidth( self.Label, self.TextScale, self.Label:GetText() )

	return self.CachedTextWidth
end

function AutoSizeText:GetTextWidth( Text )
	if not self.Label then return 0 end

	if not Text then
		return self:GetCachedTextWidth()
	end

	return GetTextWidth( self.Label, self.TextScale, Text )
end

local function GetTextHeight( Label, Scale, Text )
	Scale = Scale and Scale.y or 1
	return Label:GetTextHeight( Text ) * Scale
end

function AutoSizeText:GetCachedTextHeight()
	if self.CachedTextHeight then
		return self.CachedTextHeight
	end

	self.CachedTextHeight = GetTextHeight( self.Label, self.TextScale, self.Label:GetText() )

	return self.CachedTextHeight
end

function AutoSizeText:GetTextHeight( Text )
	if not self.Label then return 0 end

	if not Text then
		return self:GetCachedTextHeight()
	end

	return GetTextHeight( self.Label, self.TextScale, Text )
end

Shine.GUI:RegisterMixin( "AutoSizeText", AutoSizeText )
