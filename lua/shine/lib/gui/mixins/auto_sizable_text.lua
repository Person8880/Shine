--[[
	Provides auto-sizing logic based on element text.
]]

local AutoSizeText = {}

function AutoSizeText:GetContentSizeForAxis( Axis )
	if Axis == 1 then
		return self:GetTextWidth()
	end

	return self:GetTextHeight()
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
