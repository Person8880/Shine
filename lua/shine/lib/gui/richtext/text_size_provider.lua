--[[
	Provides a means of computing text sizes during wrapping operations.
]]

local SGUI = Shine.GUI

local TableEmpty = table.Empty
local TableNew = require "table.new"

local Label
local function GetLabel()
	if not Label then
		Label = SGUI:Create( "Label" )
		Label:SetIsSchemed( false )
		Label:SetIsVisible( false )
		GetLabel = function() return Label end
	end
	return Label
end

local TextSizeProvider = Shine.TypeDef()
function TextSizeProvider:Init( Font, Scale, Label )
	self.WordSizeCache = TableNew( 0, 10 )

	self.Label = Label or GetLabel()
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

	local Label = self.Label
	Label:SetFontScale( Font, Scale )

	TableEmpty( self.WordSizeCache )

	self.SpaceSize = Label:GetTextWidth( " " )
	self.TextHeight = Label:GetTextHeight( "!" )
end

function TextSizeProvider:GetWidth( Text )
	local Size = self.WordSizeCache[ Text ]
	if not Size then
		Size = GetLabel():GetTextWidth( Text )
		self.WordSizeCache[ Text ] = Size
	end
	return Size
end

return TextSizeProvider
