--[[
	Tooltip control.

	Simple pop-up box that displays a tip about something...
]]

local SGUI = Shine.GUI

local Tooltip = {}
Tooltip.IsWindow = true
-- Tooltips can't have hover focus.
Tooltip.IgnoreMouseFocus = true

SGUI.AddBoundProperty( Tooltip, "Colour", "Background:SetColor" )
SGUI.AddBoundProperty( Tooltip, "Texture", "Background:SetTexture" )

function Tooltip:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	self.Background = Background
	self.TextPadding = 16
end

function Tooltip:SetTextColour( Col )
	self.TextCol = Col

	if not self.Text then return end

	self.Text:SetColor( Col )
end

function Tooltip:SetTextPadding( TextPadding )
	self.TextPadding = TextPadding

	if not self.Text then return end

	self.Text:SetPosition( Vector2( 0, self.TextPadding * 0.5 ) )
	self:ComputeAndSetSize( self.Text:GetText() )
end

function Tooltip:SetText( Text, Font, Scale )
	local TextObj = self.Text
	if not TextObj then
		Font = Font or Fonts.kAgencyFB_Small

		TextObj = self:MakeGUITextItem()
		-- Align center doesn't want to play nice...
		TextObj:SetAnchor( 0.5, 0 )
		TextObj:SetTextAlignmentX( GUIItem.Align_Center )
		TextObj:SetFontName( Font )
		SGUI.FontManager.SetupElementForFontName( TextObj, Font )
		TextObj:SetPosition( Vector2( 0, self.TextPadding * 0.5 ) )
		TextObj:SetInheritsParentAlpha( true )
		TextObj:SetColor( self.TextCol )

		self.Background:AddChild( TextObj )
		self.Text = TextObj
	elseif Font then
		TextObj:SetFontName( Font )
		SGUI.FontManager.SetupElementForFontName( TextObj, Font )
	end

	if Scale then
		TextObj:SetScale( Scale )
	end

	self.TextScale = Scale

	TextObj:SetText( Text )
	self:ComputeAndSetSize( Text )
end

function Tooltip:UpdateText( Text )
	local TextObj = self.Text
	if not TextObj then return end

	TextObj:SetText( Text )
	self:ComputeAndSetSize( Text )
end

function Tooltip:ComputeAndSetSize( Text )
	local Scale = self.TextScale
	local WidthScale = Scale and Scale.x or 1
	local HeightScale = Scale and Scale.y or 1

	local Width = self.Text:GetTextWidth( Text ) * WidthScale + self.TextPadding
	local Height = self.Text:GetTextHeight( Text ) * HeightScale + self.TextPadding

	self:SetSize( Vector2( Width, Height ) )
end

function Tooltip:Think( DeltaTime )
	if not SGUI.EnabledMouse then
		self:FadeOut()
	end

	self.BaseClass.Think( self, DeltaTime )
	self:CallOnChildren( "Think", DeltaTime )
end

function Tooltip:FadeIn()
	local Start = self.Background:GetColor()
	local End = SGUI.CopyColour( Start )
	Start.a = 0

	self.Background:SetColor( Start )
	self:FadeTo( self.Background, Start, End, 0, 0.2 )
end

local function OnFadeOutComplete( self )
	if self.FadeOutCallback then
		self.FadeOutCallback( self.FadeOutCallbackContext )
	end
	self:Destroy()
end

function Tooltip:FadeOut( Callback, Context )
	if self.FadingOut then return end

	self.FadingOut = true
	self.FadeOutCallback = Callback
	self.FadeOutCallbackContext = Context

	local Start = self.Background:GetColor()
	local End = SGUI.ColourWithAlpha( Start, 0 )

	self:FadeTo( self.Background, Start, End, 0, 0.2, OnFadeOutComplete )
end

function Tooltip:OnLoseWindowFocus()
	self:Destroy()
end

SGUI:Register( "Tooltip", Tooltip )
