--[[
	Tooltip control.

	Simple pop-up box that displays a tip about something...
]]

local SGUI = Shine.GUI

local Tooltip = {}
Tooltip.IsWindow = true

local Texture = "ui/insight_resources.dds"

local Padding = Vector( 0, 8, 0 )

local TextureCoords = { 265, 0, 1023, 98 }

function Tooltip:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()
	Background:SetTexture( Texture )
	self.Background = Background
end

function Tooltip:SetSize( Vec )
	self.Size = Vec

	self.Background:SetSize( Vec )
	self.Background:SetTexturePixelCoordinates( TextureCoords[ 1 ], TextureCoords[ 2 ],
		TextureCoords[ 3 ], TextureCoords[ 4 ] )
end

function Tooltip:SetTextColour( Col )
	self.TextCol = Col

	if not self.Text then return end

	if self.Visible then
		self.Text:SetColor( Col )
	else
		local TextCol = SGUI.CopyColour( Col )
		TextCol.a = 0

		self.Text:SetColor( TextCol )
	end
end

function Tooltip:SetText( Text, Font, Scale )
	if self.Text then
		self.Text:SetText( Text )

		return
	end

	local TextObj = GetGUIManager():CreateTextItem()
	--Align center doesn't want to play nice...
	TextObj:SetAnchor( GUIItem.Middle, GUIItem.Top )
	TextObj:SetTextAlignmentX( GUIItem.Align_Center )
	TextObj:SetText( Text )
	TextObj:SetFontName( Font or Fonts.kAgencyFB_Small )
	TextObj:SetPosition( Padding )
	if Scale then
		TextObj:SetScale( Scale )
	end

	local WidthScale = Scale and Scale.x or 1
	local HeightScale = Scale and Scale.y or 1

	local Width = TextObj:GetTextWidth( Text ) * WidthScale + 32
	local Height = TextObj:GetTextHeight( Text ) * HeightScale + 16

	self:SetSize( Vector( Width, Height, 0 ) )

	local TextCol = self.TextCol
	TextCol.a = self.Visible and 1 or 0
	TextObj:SetColor( TextCol )

	self.Text = TextObj

	self.Background:AddChild( TextObj )
end

function Tooltip:Think( DeltaTime )
	if not SGUI.EnabledMouse then
		self:FadeOut()
	end

	self.BaseClass.Think( self, DeltaTime )
end

function Tooltip:FadeIn()
	local Start = self.Background:GetColor()
	local End = Colour( Start.r, Start.g, Start.b, 1 )

	self:FadeTo( self.Background, Start, End, 0, 0.2 )

	if not self.Text then return end

	Start = self.Text:GetColor()
	End = Colour( Start.r, Start.g, Start.b, 1 )

	self:FadeTo( self.Text, Start, End, 0, 0.2 )
end

function Tooltip:FadeOut( Callback )
	if self.FadingOut then return end

	self.FadingOut = true

	local Start = self.Background:GetColor()
	local End = Colour( Start.r, Start.g, Start.b, 0 )

	self:FadeTo( self.Background, Start, End, 0, 0.2, function()
		if Callback then
			Callback()
		end

		--Remember to remove the fade on the text!
		self:StopFade( self.Text )
		self:Destroy( true )
	end )

	if not self.Text then return end

	Start = self.Text:GetColor()
	End = Colour( Start.r, Start.g, Start.b, 0 )

	self:FadeTo( self.Text, Start, End, 0, 0.2 )
end

function Tooltip:OnLoseWindowFocus()
	self:Destroy()
end

SGUI:Register( "Tooltip", Tooltip )
