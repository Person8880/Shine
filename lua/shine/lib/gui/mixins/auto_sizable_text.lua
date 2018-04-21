--[[
	Provides auto-sizing logic based on element text.
]]

local StringGMatch = string.gmatch

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

	if Text then
		return self.Label:GetTextHeight( Text ) * Scale
	end

	local Lines = 1
	Text = self.Label:GetText()

	for Match in StringGMatch( Text, "\n" ) do
		Lines = Lines + 1
	end

	return self.Label:GetTextHeight( "!" ) * Lines * Scale
end

Shine.GUI:RegisterMixin( "AutoSizeText", AutoSizeText )
