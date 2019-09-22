--[[
	Provides a means of computing text sizes during wrapping operations.
]]

local SGUI = Shine.GUI

local CalculateTextSize = GUI and GUI.CalculateTextSize
local TableEmpty = table.Empty
local TableNew = require "table.new"

local TextSizeProvider = Shine.TypeDef()
function TextSizeProvider:Init( Font, Scale, Label )
	self.WordSizeCache = TableNew( 0, 10 )
	self:SetFontScale( Font, Scale )

	self.DefaultFont = Font
	self.DefaultScale = Scale

	return self
end

function TextSizeProvider:SetFontScale( Font, Scale )
	if not Font then
		Font = self.DefaultFont
		Scale = self.DefaultScale
	end

	if Font == self.Font and Scale == self.Scale then return end

	self.Font = Font
	self.Scale = Scale

	TableEmpty( self.WordSizeCache )

	self.SpaceSize = CalculateTextSize( Font, " " ).x
	self.TextHeight = SGUI.FontManager.GetFontSizeForFontName( Font ) or CalculateTextSize( Font, "O" ).y

	if Scale then
		self.SpaceSize = self.SpaceSize * Scale.x
		self.TextHeight = self.TextHeight * Scale.y
	end
end

function TextSizeProvider:GetWidth( Text )
	local Size = self.WordSizeCache[ Text ]
	if not Size then
		Size = CalculateTextSize( self.Font, Text ).x
		if self.Scale then
			Size = Size * self.Scale.x
		end
		self.WordSizeCache[ Text ] = Size
	end
	return Size
end

return TextSizeProvider
