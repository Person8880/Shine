--[[
	Tooltip control.

	Simple pop-up box that displays a tip about something...
]]

local SGUI = Shine.GUI

local Tooltip = {}
Tooltip.IsWindow = true

local Texture = "ui/insight_resources.dds"

local InnerPos = Vector( 1, 1, 0 )
local Padding = Vector( 16, 0, 0 )

local TextureCoords = { 265, 0, 1023, 98 }

function Tooltip:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()
	Background:SetTexture( Texture )
	self.Background = Background
end

function Tooltip:OnSchemeChange( Scheme )
	if not self.Visible then return end

	self.BorderCol = SGUI.CopyColour( Scheme.TooltipBorder )
	self.InnerCol = SGUI.CopyColour( Scheme.Tooltip )
	
	self.Background:SetColor( self.BorderCol )
	self.Inner:SetColor( self.InnerCol )

	if self.Text then
		self.Text:SetColor( Scheme.BrightText )
	end
end

function Tooltip:SetSize( Vec )
	self.Size = Vec

	self.Background:SetSize( Vec )
	self.Background:SetTexturePixelCoordinates( TextureCoords[ 1 ], TextureCoords[ 2 ],
		TextureCoords[ 3 ], TextureCoords[ 4 ] )
end

function Tooltip:SetText( Text )
	if self.Text then
		self.Text:SetText( Text )

		return
	end

	local Scheme = SGUI:GetSkin()

	local TextObj = GetGUIManager():CreateTextItem()
	TextObj:SetAnchor( GUIItem.Left, GUIItem.Middle )
	TextObj:SetTextAlignmentY( GUIItem.Align_Center )
	TextObj:SetText( Text )
	TextObj:SetFontName( Fonts.kAgencyFB_Small )
	TextObj:SetPosition( Padding )

	local Width = TextObj:GetTextWidth( Text ) + 32
	local Height = TextObj:GetTextHeight( Text ) + 16

	self:SetSize( Vector( Width, Height, 0 ) )

	if self.Visible then
		TextObj:SetColor( Scheme.BrightText )
	else
		local TextCol = SGUI.CopyColour( Scheme.BrightText )

		TextCol.a = 0
		self.TextCol = TextCol

		TextObj:SetColor( TextCol )
	end

	self.Text = TextObj
	
	self.Background:AddChild( TextObj )
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
	local Start = self.Background:GetColor()
	local End = Colour( Start.r, Start.g, Start.b, 0 )

	self:FadeTo( self.Background, Start, End, 0, 0.2, function()
		if Callback then
			Callback()
		end

		--Remember to remove the fade on the text!
		self:StopFade( self.Text )

		self:SetParent()
		self:Destroy()
	end )

	if not self.Text then return end

	Start = self.Text:GetColor()
	End = Colour( Start.r, Start.g, Start.b, 0 )

	self:FadeTo( self.Text, Start, End, 0, 0.2 )
end

function Tooltip:Cleanup()
	if self.Parent then return end
	
	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

SGUI:Register( "Tooltip", Tooltip )
