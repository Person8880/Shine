--[[
	Chat line object for the chatbox.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local SpacerElement = require "shine/lib/gui/richtext/elements/spacer"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local OSDate = os.date
local TableAdd = table.Add
local TableNew = require "table.new"

local ChatLine = {}
local TimestampColour = Colour( 0.8, 0.8, 0.8 )

function ChatLine:SetMessage( Tags, PreColour, Prefix, MessageColour, MessageText, ShowTimestamp )
	local Contents = {}
	if Tags then
		for i = 1, #Tags do
			Contents[ #Contents + 1 ] = ColourElement( Tags[ i ].Colour )
			Contents[ #Contents + 1 ] = TextElement( Tags[ i ].Text )
		end
	end

	if #Prefix > 0 then
		Contents[ #Contents + 1 ] = ColourElement( PreColour )
		Contents[ #Contents + 1 ] = TextElement( Prefix.." " )
	end

	Contents[ #Contents + 1 ] = ColourElement( MessageColour )
	Contents[ #Contents + 1 ] = TextElement( MessageText )

	self:SetContent( Contents, ShowTimestamp )
end

function ChatLine:SetContent( Contents, ShowTimestamp )
	if ShowTimestamp then
		local ContentsWithTimestamp = TableNew( #Contents + 2, 0 )

		ContentsWithTimestamp[ #ContentsWithTimestamp + 1 ] = ColourElement( TimestampColour )
		ContentsWithTimestamp[ #ContentsWithTimestamp + 1 ] = TextElement( OSDate( "%H:%M - " ) )
		TableAdd( ContentsWithTimestamp, Contents )

		Contents = ContentsWithTimestamp
	end

	self.Lines = self:ParseContents( Contents )
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

local function UpdateBackgroundSize( self )
	if self.VisibleBackground and self.MaxWidth and self.WrappedHeight then
		self.VisibleBackground:SetSize( Vector2(
			self.MaxWidth * 1.25 + self.BackgroundPadding,
			self.WrappedHeight + self.BackgroundPadding
		) )
	end
end

function ChatLine:AddBackground( Colour, Texture, Padding )
	local BackgroundElement = self.VisibleBackground

	if not BackgroundElement then
		BackgroundElement = self:MakeGUIItem()
		self.Background:AddChild( BackgroundElement )
		self.VisibleBackground = BackgroundElement
	end

	self.BackgroundColour = Colour
	self.BackgroundPadding = Padding

	BackgroundElement:SetColor( Colour )
	BackgroundElement:SetTexture( Texture )
	BackgroundElement:SetPosition( Vector2( -Padding * 0.5, -Padding * 0.5 ) )

	UpdateBackgroundSize( self )
end

function ChatLine:PerformLayout()
	if not self.ComputedWrapping then
		self:PerformWrapping()

		UpdateBackgroundSize( self )
	end
end

function ChatLine:SetBackgroundAlpha( Alpha )
	if self.FadingOut then return end

	if self.BackgroundColour then
		self.BackgroundColour.a = Alpha
	end

	self:MakeVisible()
end

function ChatLine:FadeIn( Duration, Easer )
	Duration = Duration or 0.25

	self:ApplyTransition( {
		Type = "Alpha",
		StartValue = 0,
		EndValue = 1,
		Duration = Duration,
		EasingFunction = Easer
	} )

	if self.VisibleBackground then
		self:ApplyTransition( {
			Type = "Alpha",
			Element = self.VisibleBackground,
			StartValue = 0,
			EndValue = self.BackgroundColour.a,
			Duration = Duration,
			EasingFunction = Easer
		} )
	end
end

function ChatLine:MakeVisible()
	self:StopAlpha()
	self:SetAlpha( 1 )

	if self.VisibleBackground then
		self:StopAlpha( self.VisibleBackground )
		self.VisibleBackground:SetColor( self.BackgroundColour )
	end
end

function ChatLine:FadeOutIn( Delay, Duration, OnComplete, Easer )
	if self.FadeOutTimer then
		self.FadeOutTimer:Destroy()
	end

	self.FadeOutTimer = Shine.Timer.Simple( Delay, function()
		self.FadeOutTimer = nil

		if not self.Parent:GetIsVisible() then
			-- Skip fading if currently invisible.
			return OnComplete()
		end

		self:FadeOut( Duration, OnComplete, Easer )
	end )
end

function ChatLine:FadeOut( Duration, OnComplete, Easer )
	if self.FadingOut then return end

	self.FadingOut = true

	if self.FadeOutTimer then
		self.FadeOutTimer:Destroy()
		self.FadeOutTimer = nil
	end

	self:ApplyTransition( {
		Type = "Alpha",
		EndValue = 0,
		Duration = Duration,
		Callback = OnComplete,
		EasingFunction = Easer
	} )

	if self.VisibleBackground then
		self:ApplyTransition( {
			Type = "Alpha",
			Element = self.VisibleBackground,
			EndValue = 0,
			Duration = Duration,
			EasingFunction = Easer
		} )
	end
end

function ChatLine:Reset()
	self:MakeVisible()
	self.FadingOut = false
	if self.FadeOutTimer then
		self.FadeOutTimer:Destroy()
		self.FadeOutTimer = nil
	end
end

function ChatLine:Cleanup()
	self.BaseClass.Cleanup( self )

	if self.FadeOutTimer then
		self.FadeOutTimer:Destroy()
	end
end

SGUI:Register( "ChatLine", ChatLine, "RichText" )
