--[[
	List header.
]]

local SGUI = Shine.GUI

local ListHeader = {}

local Padding = Vector( 10, 0, 0 )

function ListHeader:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background

	local SortIndicator = SGUI:Create( "Label", self )
	SortIndicator:SetFont( SGUI.Fonts.Ionicons )
	SortIndicator:SetText( "" )
	SortIndicator:SetAnchor( "CenterRight" )
	SortIndicator:SetTextAlignmentY( GUIItem.Align_Center )
	SortIndicator:SetTextAlignmentX( GUIItem.Align_Max )
	SortIndicator:SetPos( Vector2( -8, 0 ) )

	self.SortIndicator = SortIndicator

	self:SetHighlightOnMouseOver( true )
end

function ListHeader:SetText( Text )
	if self.TextObj then
		self.TextObj:SetText( Text )

		return
	end

	local TextObj = self:MakeGUITextItem()
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

function ListHeader:SetSorted( IsSorted, Descending )
	if not IsSorted then
		self.SortIndicator:SetText( "" )
		return
	end

	-- Update the sorting indicator to point in the sorting direction.
	local Font, Scale = SGUI.FontManager.GetFontForAbsoluteSize(
		SGUI.FontFamilies.Ionicons,
		self:GetSize().y
	)
	self.SortIndicator:SetFontScale( Font, Scale )

	local IconName = Descending and "ChevronDown" or "ChevronUp"
	self.SortIndicator:SetText( SGUI.Icons.Ionicons[ IconName ] )
	self.SortIndicator:SetColour( self.TextColour )
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

SGUI:Register( "ListHeader", ListHeader, "Button" )
