--[[
	Tooltip control.

	Simple pop-up box that displays a tip about something...
]]

local SGUI = Shine.GUI

local Tooltip = {}

local InnerPos = Vector( 1, 1, 0 )
local Padding = Vector( 5, 0, 0 )

function Tooltip:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()

	self.Background = Background

	local Inner = Manager:CreateGraphicItem()
	Inner:SetAnchor( GUIItem.Left, GUIItem.Top )
	Inner:SetPosition( InnerPos )

	Background:AddChild( Inner )

	self.Inner = Inner

	local Scheme = SGUI:GetSkin()

	local BorderCol = SGUI.CopyColour( Scheme.TooltipBorder )
	local InnerCol = SGUI.CopyColour( Scheme.Tooltip )

	BorderCol.a = 0
	InnerCol.a = 0

	self.BorderCol = BorderCol
	self.InnerCol = InnerCol

	Background:SetColor( BorderCol )
	Inner:SetColor( InnerCol )
end

function Tooltip:OnSchemeChange( Scheme )
	if not self.Visible then return end

	self.BorderCol = SGUI.CopyColour( Scheme.TooltipBorder )
	self.InnerCol = SGUI.CopyColour( Scheme.Tooltip )
	
	self.Background:SetColor( self.BorderCol )
	self.Inner:SetColor( self.InnerCol )

	if self.Text then
		self.Text:SetColor( Scheme.DarkText )
	end
end

function Tooltip:SetSize( Vec )
	self.Size = Vec

	self.Background:SetSize( Vec )
	self.Inner:SetSize( Vector( Vec.x - 2, Vec.y - 2, 0 ) )
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
	TextObj:SetPosition( Padding )

	local Width = TextObj:GetTextWidth( Text ) + 10
	local Height = TextObj:GetTextHeight( Text ) + 5

	self:SetSize( Vector( Width, Height, 0 ) )

	if self.Visible then
		TextObj:SetColor( Scheme.DarkText )
	else
		local TextCol = SGUI.CopyColour( Scheme.DarkText )

		TextCol.a = 0
		self.TextCol = TextCol

		TextObj:SetColor( TextCol )
	end

	self.Text = TextObj
	
	self.Background:AddChild( TextObj )
end

function Tooltip:FadeIn()
	local Start = self.BorderCol
	Start.a = 0

	local End = SGUI.CopyColour( self.BorderCol )
	End.a = 255

	self:FadeTo( self.Background, Start, End, 0, 0.5, function( Background )
		Background:SetColor( End )
	end )

	local InStart = self.InnerCol
	InStart.a = 0

	local InEnd = SGUI.CopyColour( self.InnerCol )
	InEnd.a = 255

	self:FadeTo( self.Inner, InStart, InEnd, 0, 0.5, function( Inner )
		Inner:SetColor( InEnd )
	end )

	local TextStart = self.TextCol

	if not TextStart then return end
	TextStart.a = 0

	local TextEnd = SGUI.CopyColour( self.TextCol )
	TextEnd.a = 255

	self:FadeTo( self.Text, TextStart, TextEnd, 0, 0.5, function( TextObj )
		TextObj:SetColor( TextEnd )
	end )

	local EndPos = self.Background:GetPosition() + Vector( 0, -self.Size.y, 0 )
	self:SetPos( EndPos )
end

function Tooltip:FadeOut()
	local Start = self.BorderCol
	Start.a = 255

	local End = SGUI.CopyColour( self.BorderCol )
	End.a = 0

	self:FadeTo( self.Background, Start, End, 0, 0.25, function( Background )
		return
	end )

	local InStart = self.InnerCol
	InStart.a = 255

	local InEnd = SGUI.CopyColour( self.InnerCol )
	InEnd.a = 0

	self:FadeTo( self.Inner, InStart, InEnd, 0, 0.25, function( Inner )
		return
	end )

	local TextStart = self.TextCol

	if not TextStart then return end

	TextStart.a = 255

	local TextEnd = SGUI.CopyColour( self.TextCol )
	TextEnd.a = 0

	self:FadeTo( self.Text, TextStart, TextEnd, 0, 0.25, function( TextObj )
		self:SetParent()
		self:Destroy()
	end )
end

function Tooltip:Cleanup()
	if self.Parent then return end
	
	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

SGUI:Register( "Tooltip", Tooltip )
