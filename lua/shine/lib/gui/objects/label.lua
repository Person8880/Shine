--[[
	Basically a GUI text item bound to SGUI.
]]

local SGUI = Shine.GUI

local StringGMatch = string.gmatch

local Label = {}

local ZeroCol = Colour( 0, 0, 0, 0 )

SGUI.AddBoundProperty( Label, "Colour", "Label:SetColor" )
SGUI.AddBoundProperty( Label, "Font", "Label:SetFontName", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "Text", "Label", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "TextAlignmentX", "Label" )
SGUI.AddBoundProperty( Label, "TextAlignmentY", "Label" )
SGUI.AddBoundProperty( Label, "TextScale", "Label:SetScale", { "InvalidatesParent" } )

function Label:Initialise()
	self.BaseClass.Initialise( self )

	local Text = GetGUIManager():CreateTextItem()
	self.Label = Text
	self.Background = self.Label
	self.Bright = false

	local Skin = SGUI:GetSkin()

	Text:SetColor( Skin.DarkText )

	self.TextScale = Vector( 1, 1, 0 )
end

function Label:OnSchemeChange( Skin )
	local Colour = self.Bright and Skin.BrightText or Skin.DarkText

	self.Label:SetColor( Colour )
end

function Label:SetupStencil()
	self.Label:SetInheritsParentStencilSettings( false )
	self.Label:SetStencilFunc( GUIItem.NotEqual )
end

function Label:SetSize() end

function Label:GetSize()
	return Vector( self:GetTextWidth(), self:GetTextHeight(), 0 )
end

function Label:GetTextWidth( Text )
	local Scale = self.TextScale
	Scale = Scale and Scale.x or 1

	return self.Label:GetTextWidth( Text or self.Label:GetText() ) * Scale
end

function Label:GetTextHeight( Text )
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

function Label:SetBright( Bright )
	self.Bright = Bright and true or false

	local Skin = SGUI:GetSkin()
	self.Label:SetColor( Bright and Skin.BrightText or Skin.DarkText )
end

SGUI:Register( "Label", Label )
