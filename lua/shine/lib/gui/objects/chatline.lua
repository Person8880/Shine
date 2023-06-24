--[[
	Chat line object for the chatbox.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local SpacerElement = require "shine/lib/gui/richtext/elements/spacer"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local Max = math.max
local OSDate = os.date
local StringSub = string.sub
local TableAdd = table.Add
local TableNew = require "table.new"
local tostring = tostring

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

do
	local function ComputeWidth( self, TextSizeProvider )
		local Hours = StringSub( self.Value, 1, 2 )

		local MaxWidth = 0
		for i = 0, 9 do
			MaxWidth = Max( MaxWidth, TextSizeProvider:GetWidth( tostring( i ) ) )
		end

		-- Make sure all timestamps have the same width (for the current hour).
		return MaxWidth * 2 + TextSizeProvider:GetWidth( ":" ) + TextSizeProvider:GetWidth( Hours )
	end

	function ChatLine:SetContent( Contents, ShowTimestamp )
		if ShowTimestamp then
			local ContentsWithTimestamp = TableNew( #Contents + 4, 0 )

			ContentsWithTimestamp[ #ContentsWithTimestamp + 1 ] = ColourElement( TimestampColour )
			ContentsWithTimestamp[ #ContentsWithTimestamp + 1 ] = TextElement( {
				Value = OSDate( "%H:%M" ),
				ComputeWidth = ComputeWidth
			} )
			ContentsWithTimestamp[ #ContentsWithTimestamp + 1 ] = TextElement( " " )
			TableAdd( ContentsWithTimestamp, Contents )

			Contents = ContentsWithTimestamp
		end

		self.Lines = self:ParseContents( Contents )
		self:InvalidateWrapping()
	end
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
	BackgroundElement:SetInheritsParentAlpha( true )

	UpdateBackgroundSize( self )
end

function ChatLine:SetBackgroundTextureCoordinates( X1, Y1, X2, Y2 )
	if not self.VisibleBackground then return end

	self.VisibleBackground:SetTextureCoordinates( X1, Y1, X2, Y2 )
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
		self.VisibleBackground:SetColor( self.BackgroundColour )
	end

	self:MakeVisible()
end

function ChatLine:FadeIn( Duration, Easer )
	Duration = Duration or 0.25

	self:ApplyTransition( {
		Type = "AlphaMultiplier",
		StartValue = 0,
		EndValue = 1,
		Duration = Duration,
		EasingFunction = Easer
	} )
end

function ChatLine:MakeVisible()
	self:StopEasingType( "AlphaMultiplier" )
	self:SetAlphaMultiplier( 1 )
end

local function OnFadeOutDelayPassed( Timer )
	local Data = Timer.Data

	local ChatLineInstance = Data.ChatLine
	if not SGUI.IsValid( ChatLineInstance ) then return end

	ChatLineInstance.FadeOutTimer = nil

	if not ChatLineInstance.Parent:GetIsVisible() then
		-- Skip fading if currently invisible.
		return Data.OnComplete()
	end

	ChatLineInstance:FadeOut( Data.Duration, Data.OnComplete, Data.Easer )
end

function ChatLine:FadeOutIn( Delay, Duration, OnComplete, Easer )
	if self.FadeOutTimer then
		self.FadeOutTimer:Destroy()
	end

	self.FadeOutTimer = Shine.Timer.Simple( Delay, OnFadeOutDelayPassed, {
		ChatLine = self,
		Duration = Duration,
		OnComplete = OnComplete,
		Easer = Easer
	} )
end

function ChatLine:FadeOut( Duration, OnComplete, Easer )
	if self.FadingOut then return end

	self.FadingOut = true

	if self.FadeOutTimer then
		self.FadeOutTimer:Destroy()
		self.FadeOutTimer = nil
	end

	self:ApplyTransition( {
		Type = "AlphaMultiplier",
		EndValue = 0,
		Duration = Duration,
		Callback = OnComplete,
		EasingFunction = Easer
	} )
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
