--[[
	List header.
]]

local SGUI = Shine.GUI

local ListHeader = {}

local Padding = Vector( 10, 0, 0 )

function ListHeader:Initialise()
	self.BaseClass.Initialise( self )

	local Background = GetGUIManager():CreateGraphicItem()

	self.Background = Background

	local Scheme = SGUI:GetSkin()

	Background:SetColor( Scheme.List.HeaderColour )

	self.ActiveCol = Scheme.List.ActiveHeaderColour
	self.InactiveCol = Scheme.List.HeaderColour

	self:SetHighlightOnMouseOver( true )
end

function ListHeader:OnSchemeChange( Scheme )
	if not self.UseScheme then return end

	self.ActiveCol = Scheme.List.ActiveHeaderColour
	self.InactiveCol = Scheme.List.HeaderColour

	self.Background:SetColor( self.Highlighted and self.ActiveCol or self.InactiveCol )

	self.TextColour = Scheme.List.HeaderTextColour or Scheme.BrightText

	if self.TextObj then
		self.TextObj:SetColor( self.TextColour )
	end
end

function ListHeader:SetText( Text )
	if self.TextObj then
		self.TextObj:SetText( Text )

		return
	end

	local TextObj = GetGUIManager():CreateTextItem()
	TextObj:SetAnchor( GUIItem.Left, GUIItem.Center )
	TextObj:SetText( Text )
	TextObj:SetTextAlignmentY( GUIItem.Align_Center )
	TextObj:SetPosition( Padding )
	if self.Font then
		TextObj:SetFont( self.Font )
	end
	if self.TextScale then
		TextObj:SetScale( self.TextScale )
	end

	self.Background:AddChild( TextObj )

	local Scheme = SGUI:GetSkin()

	TextObj:SetColor( self.TextColour or Scheme.BrightText )

	self.TextObj = TextObj
end

function ListHeader:SetTextScale( Scale )
	self.TextScale = Scale

	if not self.TextObj then return end

	self.TextObj:SetScale( Scale )
end

function ListHeader:SetFont( Font )
	self.Font = Font

	if not self.TextObj then return end

	self.TextObj:SetFontName( Font )
end

function ListHeader:SetTextColour( Col )
	self.TextColour = Col

	if not self.TextObj then return end

	self.TextObj:SetColor( Col )
end

function ListHeader:SetSize( Size )
	self.Size = Size

	self.Background:SetSize( Size )
end

function ListHeader:GetSize()
	return self.Size
end

function ListHeader:GetIsVisible()
	if not self.Parent:GetIsVisible() then return false end

	return self.Background:GetIsVisible()
end

function ListHeader:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Background, self.HighlightMult ) then return end

	return true, self
end

function ListHeader:OnMouseUp( Key )
	if not self:GetIsVisible() then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Background, self.HighlightMult ) then return end

	self.Parent:SortRows( self.Index )
	Shared.PlaySound( nil, SGUI.Controls.Button.Sound )

	return true
end

function ListHeader:Think( DeltaTime )
	if not self:GetIsVisible() then return end

	self.BaseClass.Think( self, DeltaTime )
end

SGUI:Register( "ListHeader", ListHeader )
