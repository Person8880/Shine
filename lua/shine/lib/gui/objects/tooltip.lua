--[[
	Tooltip control.

	Simple pop-up box that displays a tip about something...
]]

local SGUI = Shine.GUI

local Tooltip = {}
Tooltip.IsWindow = true

local Padding = Vector( 0, 8, 0 )

SGUI.AddBoundProperty( Tooltip, "Colour", "Background:SetColor" )
SGUI.AddBoundProperty( Tooltip, "Texture", "Background:SetTexture" )
SGUI.AddBoundProperty( Tooltip, "TexturePixelCoordinates", "Background:SetTexturePixelCoordinates" )

function Tooltip:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()
	self.Background = Background
end

function Tooltip:SetSize( Vec )
	self.Size = Vec
	self.Background:SetSize( Vec )
end

function Tooltip:SetTextColour( Col )
	self.TextCol = Col

	if not self.Text then return end

	self.Text:SetColor( Col )
end

function Tooltip:SetText( Text, Font, Scale )
	local TextObj = self.Text
	if not TextObj then
		TextObj = GetGUIManager():CreateTextItem()
		-- Align center doesn't want to play nice...
		TextObj:SetAnchor( GUIItem.Middle, GUIItem.Top )
		TextObj:SetTextAlignmentX( GUIItem.Align_Center )
		TextObj:SetFontName( Font or Fonts.kAgencyFB_Small )
		TextObj:SetPosition( Padding )
		TextObj:SetInheritsParentAlpha( true )
		TextObj:SetColor( self.TextCol )

		self.Background:AddChild( TextObj )
		self.Text = TextObj
	elseif Font then
		TextObj:SetFontName( Font )
	end

	if Scale then
		TextObj:SetScale( Scale )
	end

	TextObj:SetText( Text )

	local WidthScale = Scale and Scale.x or 1
	local HeightScale = Scale and Scale.y or 1

	local Width = TextObj:GetTextWidth( Text ) * WidthScale + 16
	local Height = TextObj:GetTextHeight( Text ) * HeightScale + 16

	self:SetSize( Vector2( Width, Height ) )
end

function Tooltip:Think( DeltaTime )
	if not SGUI.EnabledMouse then
		self:FadeOut()
	end

	self.BaseClass.Think( self, DeltaTime )
end

function Tooltip:FadeIn()
	local Start = self.Background:GetColor()
	local End = SGUI.CopyColour( Start )
	Start.a = 0

	self.Background:SetColor( Start )
	self:FadeTo( self.Background, Start, End, 0, 0.2 )
end

function Tooltip:FadeOut( Callback )
	if self.FadingOut then return end

	self.FadingOut = true

	local Start = self.Background:GetColor()
	local End = SGUI.ColourWithAlpha( Start, 0 )

	self:FadeTo( self.Background, Start, End, 0, 0.2, function()
		if Callback then
			Callback()
		end
		self:Destroy()
	end )
end

function Tooltip:OnLoseWindowFocus()
	self:Destroy()
end

SGUI:Register( "Tooltip", Tooltip )
