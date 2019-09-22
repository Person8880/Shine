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

SGUI.AddProperty( ChatLine, "PreMargin" )

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
		Contents[ #Contents + 1 ] = TextElement( Prefix )
		Contents[ #Contents + 1 ] = SpacerElement( {
			AutoWidth = self.PreMargin,
			IgnoreOnNewLine = true
		} )
	end

	Contents[ #Contents + 1 ] = ColourElement( MessageColour )
	Contents[ #Contents + 1 ] = TextElement( MessageText )

	self:SetContent( Contents, ShowTimestamp )
end

function ChatLine:SetContent( Contents, ShowTimestamp )
	if ShowTimestamp then
		local ContentsWithTimestamp = TableNew( 0, #Contents + 2 )

		ContentsWithTimestamp[ #ContentsWithTimestamp + 1 ] = ColourElement( TimestampColour )
		ContentsWithTimestamp[ #ContentsWithTimestamp + 1 ] = TextElement( OSDate( "%H:%M - " ) )
		TableAdd( ContentsWithTimestamp, Contents )

		Contents = ContentsWithTimestamp
	end

	self.Lines = self:ParseContents( Contents )
	self.ComputedWrapping = false
	self:InvalidateLayout()
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
	if self.MaxWidth and self.WrappedHeight then
		BackgroundElement:SetSize( Vector2( self.MaxWidth + Padding, self.WrappedHeight + Padding ) )
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
	self:AlphaTo( nil, 0, 1, 0, Duration, nil, Easer )

	if self.VisibleBackground then
		self:AlphaTo( self.VisibleBackground, 0, self.BackgroundColour.a, 0, Duration, nil, Easer )
	end
end

function ChatLine:MakeVisible()
	self:StopAlpha()
	self.RootElement:SetAlpha( 1 )

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

	self:AlphaTo( nil, nil, 0, 0, Duration, OnComplete, Easer )

	if self.VisibleBackground then
		self:AlphaTo( self.VisibleBackground, nil, 0, 0, Duration, nil, Easer )
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
