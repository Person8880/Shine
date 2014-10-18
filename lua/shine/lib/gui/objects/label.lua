--[[
	Basically a GUI text item bound to SGUI.
]]

local SGUI = Shine.GUI

local StringGMatch = string.gmatch

local Label = {}

local ZeroCol = Colour( 0, 0, 0, 0 )

function Label:Initialise()
	self.BaseClass.Initialise( self )

	local Text = GetGUIManager():CreateTextItem()
	self.Text = Text

	self.Background = self.Text

	self.Bright = false

	local Skin = SGUI:GetSkin()

	Text:SetColor( Skin.DarkText )

	self.TextScale = Vector( 1, 1, 0 )
end

function Label:OnSchemeChange( Skin )
	local Colour = self.Bright and Skin.BrightText or Skin.DarkText

	self.Text:SetColor( Colour )
end

function Label:SetupStencil()
	self.Text:SetInheritsParentStencilSettings( false )
	self.Text:SetStencilFunc( GUIItem.NotEqual )
end

function Label:SetText( Text )
	self.Text:SetText( Text )
end

function Label:GetText()
	return self.Text:GetText()
end

function Label:GetSize()
	return Vector( self:GetTextWidth() * self.TextScale.x,
		self:GetTextHeight() * self.TextScale.y, 0 )
end

function Label:SetTextAlignmentX( Align )
	self.Text:SetTextAlignmentX( Align )
end

function Label:SetTextAlignmentY( Align )
	self.Text:SetTextAlignmentY( Align )
end

function Label:SetTextScale( Scale )
	self.Text:SetScale( Scale )

	self.TextScale = Scale
end

function Label:GetTextWidth( Text )
	return self.Text:GetTextWidth( Text or self.Text:GetText() )
end

function Label:GetTextHeight( Text )
	if Text then
		return self.Text:GetTextHeight( Text )
	end

	local Lines = 1
	Text = self.Text:GetText()

	for Match in StringGMatch( Text, "\n" ) do
		Lines = Lines + 1
	end

	return self.Text:GetTextHeight( "!" ) * Lines
end

function Label:SetFont( Name )
	self.Text:SetFontName( Name )
end

function Label:SetBright( Bright )
	self.Bright = Bright and true or false

	local Skin = SGUI:GetSkin()
	self.Text:SetColor( Bright and Skin.BrightText or Skin.DarkText )
end

function Label:SetColour( Col )
	self.Text:SetColor( Col )
end

function Label:GetColour()
	return self.Text:GetColor()
end

SGUI:Register( "Label", Label )
