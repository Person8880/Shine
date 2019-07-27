--[[
	Chat line object for the chatbox.
]]

local SGUI = Shine.GUI

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local SpacerElement = require "shine/lib/gui/richtext/elements/spacer"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local OSDate = os.date

local ChatLine = {}
local BackgroundColour = Colour( 0, 0, 0, 0 )
local TimestampColour = Colour( 0.8, 0.8, 0.8 )

SGUI.AddProperty( ChatLine, "LineSpacing" )
SGUI.AddProperty( ChatLine, "PreMargin" )

function ChatLine:Initialise()
	self:SetIsSchemed( false )

	self.Background = self:MakeGUIItem()
	self.Background:SetColor( BackgroundColour )

	self.WrappedWidth = 0
	self.WrappedHeight = 0
end

function ChatLine:SetFont( Font )
	if self.Font == Font then return end

	self.Font = Font

	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function ChatLine:SetTextScale( Scale )
	if self.TextScale == Scale then return end

	self.TextScale = Scale

	self.ComputedWrapping = false
	self:InvalidateLayout()
end

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

function ChatLine:PerformLayout()
	if not self.ComputedWrapping then
		self:PerformWrapping()

		if self.VisibleBackground and self.MaxWidth and self.WrappedHeight then
			self.VisibleBackground:SetSize( Vector2(
				self.MaxWidth + self.BackgroundPadding,
				self.WrappedHeight + self.BackgroundPadding
			) )
		end
	end
end

function ChatLine:SetSize( Size )
	if self.MaxWidth == Size.x and self.ComputedWrapping then return end

	self.MaxWidth = Size.x
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function ChatLine:GetComputedSize( Index, ParentSize )
	if Index == 1 then
		return ParentSize
	end

	return self:GetSize().y
end

function ChatLine:GetSize()
	if not self.ComputedWrapping and self.MaxWidth then
		-- Ensure wrapping is computed before returning the size, otherwise we may return an older
		-- size value if we've been re-used.
		self:InvalidateLayout( true )
	end

	return Vector2( self.WrappedWidth, self.WrappedHeight )
end

local Multimap = Shine.Multimap

local Max = math.max
local TableEmpty = table.Empty
local TableNew = require "table.new"
local TableRemove = table.remove

-- Parses a flat list of text/colours/elements into a list of lines, based on the line breaks
-- in each text element. These lines will be wrapped individually when the layout is computed.
function ChatLine:ParseContents( Contents, ShowTimestamp )
	local Lines = {}
	local Elements = TableNew( #Contents, 0 )

	if ShowTimestamp then
		Elements[ #Elements + 1 ] = ColourElement( TimestampColour )
		Elements[ #Elements + 1 ] = TextElement( OSDate( "%H:%M - " ) )
	end

	for i = 1, #Contents do
		Elements[ #Elements + 1 ] = Contents[ i ]

		local CurrentElement = Elements[ #Elements ]
		local ElementLines = CurrentElement:GetLines()
		if ElementLines then
			Elements[ #Elements ] = ElementLines[ 1 ]
			for j = 2, #ElementLines do
				Lines[ #Lines + 1 ] = Elements
				Elements = { ElementLines[ j ] }
			end
		end
	end

	if #Elements > 0 then
		Lines[ #Lines + 1 ] = Elements
	end

	return Lines
end

function ChatLine:SetContent( Contents, ShowTimestamp )
	self.Lines = self:ParseContents( Contents, ShowTimestamp )
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

function ChatLine:RestoreFromLines( Lines )
	self.Lines = Lines
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

local Wrapper = require "shine/lib/gui/richtext/wrapper"

function ChatLine:PerformWrapping()
	local Lines = self.Lines
	local MaxWidth = self.MaxWidth
	if not MaxWidth or not Lines then return end

	local Start = Shared.GetSystemTimeReal()

	local WrappedLines = Wrapper.WordWrapRichTextLines( {
		Lines = Lines,
		MaxWidth = MaxWidth,
		Font = self.Font,
		TextScale = self.TextScale
	} )

	LuaPrint( "Computed wrapping in", ( Shared.GetSystemTimeReal() - Start ) * 1e6 )

	Start = Shared.GetSystemTimeReal()

	self:ApplyLines( WrappedLines )
	self.ComputedWrapping = true

	LuaPrint( "Applied wrapped lines in", ( Shared.GetSystemTimeReal() - Start ) * 1e6 )
end

local function MakeElement( self, Class )
	local Elements = self.ElementPool and self.ElementPool:Get( Class )

	local Element
	if Elements then
		-- It's OK to do this here as we don't care about the multimap other than
		-- to hold lists of elements.
		Element = TableRemove( Elements )
	end

	return Element or SGUI:Create( Class )
end

local CreatedElements = TableNew( 30, 0 )
function ChatLine:ApplyLines( Lines )
	local ElementPool
	if self.Children then
		ElementPool = Multimap()
		for Child in self.Children:Iterate() do
			ElementPool:Add( Child.Class, Child )
		end
	end

	local Context = {
		CurrentFont = self.Font,
		CurrentScale = self.TextScale,
		DefaultFont = self.Font,
		DefaultScale = self.TextScale,
		CurrentColour = Colour( 1, 1, 1, 1 ),
		ElementPool = ElementPool,
		MakeElement = MakeElement
	}

	local Parent = self
	local YOffset = 0
	local MaxWidth = 0
	local Spacing = self.LineSpacing:GetValue()
	local RootLineElements = {}

	for i = 1, #Lines do
		local Line = Lines[ i ]

		local RootControl
		local LineWidth = 0
		local LineHeight = 0
		local ElementCount = 0
		local NeedsAlignment = false

		for j = 1, #Line do
			Context.CurrentIndex = j

			local Element = Line[ j ]

			local Control = Element:MakeElement( Context )
			if Control then
				ElementCount = ElementCount + 1
				CreatedElements[ ElementCount ] = Control

				Control:SetParent( self, Parent.Background )
				if Parent ~= self then
					-- Make each element start from where the previous one ends.
					Control:SetInheritsParentAlpha( true )

					Control:SetPos( Vector2( LineWidth + ( Context.NextMargin or 0 ), 0 ) )
					Context.NextMargin = nil
				else
					Control:SetInheritsParentAlpha( false )

					RootLineElements[ i ] = Control
					Control:SetPos( Vector2( 0, YOffset ) )

					Parent = Control
				end

				local Size = Control:GetSize()
				LineWidth = LineWidth + Size.x
				NeedsAlignment = NeedsAlignment or ( LineHeight ~= 0 and Size.y ~= LineHeight )
				LineHeight = Max( LineHeight, Size.y )
			end
		end

		-- Align all items in the line centrally to avoid one larger element looking out of place.
		if NeedsAlignment then
			local FirstOffset
			for i = 1, ElementCount do
				local Pos = CreatedElements[ i ]:GetPos()

				local Offset = LineHeight * 0.5 - CreatedElements[ i ]:GetSize().y * 0.5
				Pos.y = Pos.y + Offset

				if i == 1 then
					FirstOffset = Offset
				else
					-- As all elements in the line are parented to the first, if the first element was not the tallest then
					-- all subsequent elements need to move up by the offset from it.
					Pos.y = Pos.y - FirstOffset
				end

				CreatedElements[ i ]:SetPos( Pos )
			end
		end

		Context.NextMargin = nil

		Parent = self
		MaxWidth = Max( MaxWidth, LineWidth )
		YOffset = YOffset + LineHeight + Spacing
	end

	TableEmpty( CreatedElements )

	self.WrappedWidth = MaxWidth
	self.WrappedHeight = YOffset - Spacing
	self.RootLineElements = RootLineElements

	-- Any unused elements left behind should be destroyed.
	if ElementPool then
		for Class, Elements in ElementPool:Iterate() do
			for i = 1, #Elements do
				Elements[ i ]:Destroy()
			end
		end
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
	if self.MaxWidth and self.WrappedHeight then
		BackgroundElement:SetSize( Vector2( self.MaxWidth + Padding, self.WrappedHeight + Padding ) )
	end
end

function ChatLine:SetAlpha( Alpha )
	if self.FadingOut then return end

	if self.BackgroundColour then
		self.BackgroundColour.a = Alpha
	end

	self:MakeVisible()
end

function ChatLine:FadeIn( Duration, Easer )
	Duration = Duration or 0.25
	self:ForEach( "RootLineElements", "AlphaTo", nil, 0, 1, 0, Duration, nil, Easer )

	if self.VisibleBackground then
		self:AlphaTo( self.VisibleBackground, 0, self.BackgroundColour.a, 0, Duration, nil, Easer )
	end
end

function ChatLine:MakeVisible()
	local RootLineElements = self.RootLineElements
	for i = 1, #RootLineElements do
		local Element = RootLineElements[ i ]
		self:StopAlpha( Element )

		local Colour = Element.Background:GetColor()
		Colour.a = 1
		Element.Background:SetColor( Colour )
	end

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

	local RootElements = self.RootLineElements
	for i = 1, #RootElements do
		local Element = RootElements[ i ]
		Element:AlphaTo( nil, nil, 0, 0, Duration, i == 1 and OnComplete, Easer )
	end

	if self.VisibleBackground then
		self:AlphaTo( self.VisibleBackground, nil, 0, 0, Duration, nil, Easer )
	end
end

function ChatLine:Reset()
	local RootElements = self.RootLineElements
	for i = 1, #RootElements do
		local Element = RootElements[ i ]
		Element:StopAlpha()
	end

	if self.VisibleBackground then
		self:StopAlpha( self.VisibleBackground )
	end

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

SGUI:Register( "ChatLine", ChatLine )
