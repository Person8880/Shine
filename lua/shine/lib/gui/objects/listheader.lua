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
	self:SetHighlightOnMouseOver( true )
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
	TextObj:SetColor( self.TextColour )
	if self.Font then
		TextObj:SetFontName( self.Font )
	end
	if self.TextScale then
		TextObj:SetScale( self.TextScale )
	end

	self.Background:AddChild( TextObj )
	self.TextObj = TextObj
end

SGUI.AddBoundProperty( ListHeader, "Font", "TextObj:SetFontName" )
SGUI.AddBoundProperty( ListHeader, "TextColour", "TextObj:SetColor" )
SGUI.AddBoundProperty( ListHeader, "TextScale", "TextObj:SetScale" )

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

SGUI:Register( "ListHeader", ListHeader, "Button" )
