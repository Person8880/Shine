--[[
	Basically a GUI text item bound to SGUI.
]]

local SGUI = Shine.GUI

local Label = {}

SGUI.AddBoundProperty( Label, "Colour", "Label:SetColor" )
SGUI.AddBoundProperty( Label, "InheritsParentAlpha", "Label" )
SGUI.AddBoundProperty( Label, "Font", "Label:SetFontName", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "Text", "Label", { "InvalidatesParent" } )
SGUI.AddBoundProperty( Label, "TextAlignmentX", "Label" )
SGUI.AddBoundProperty( Label, "TextAlignmentY", "Label" )
SGUI.AddBoundProperty( Label, "TextScale", "Label:SetScale", { "InvalidatesParent" } )

function Label:Initialise()
	self.BaseClass.Initialise( self )

	self.Label = GetGUIManager():CreateTextItem()
	self.Background = self.Label
	self.TextScale = Vector( 1, 1, 0 )
end

function Label:MouseIn( Element, Mult, MaxX, MaxY )
	return self:MouseInControl( Mult, MaxX, MaxY )
end

function Label:GetScreenPos()
	local Pos = self.BaseClass.GetScreenPos( self )
	local Size = self:GetSize()

	local XAlign = self:GetTextAlignmentX()
	if XAlign == GUIItem.Align_Center then
		Pos.x = Pos.x - Size.x * 0.5
	elseif XAlign == GUIItem.Align_Max then
		Pos.x = Pos.x - Size.x
	end

	local YAlign = self:GetTextAlignmentY()
	if YAlign == GUIItem.Align_Center then
		Pos.y = Pos.y - Size.y * 0.5
	elseif YAlign == GUIItem.Align_Max then
		Pos.y = Pos.y - Size.y
	end

	return Pos
end

function Label:SetupStencil()
	self.Label:SetInheritsParentStencilSettings( false )
	self.Label:SetStencilFunc( GUIItem.NotEqual )
end

function Label:SetSize() end

function Label:GetSize()
	return Vector( self:GetTextWidth(), self:GetTextHeight(), 0 )
end

function Label:SetBright( Bright )
	-- Deprecated, does nothing.
end

SGUI:AddMixin( Label, "AutoSizeText" )
SGUI:AddMixin( Label, "Clickable" )
SGUI:Register( "Label", Label )
