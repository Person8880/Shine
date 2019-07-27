--[[
	Chat line object for the chatbox.
]]

local SGUI = Shine.GUI

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
			Contents[ #Contents + 1 ] = Tags[ i ].Colour
			Contents[ #Contents + 1 ] = Tags[ i ].Text
		end
	end

	if #Prefix > 0 then
		Contents[ #Contents + 1 ] = PreColour
		Contents[ #Contents + 1 ] = Prefix
		Contents[ #Contents + 1 ] = {
			Type = "Spacer",
			AutoWidth = self.PreMargin,
			IgnoreOnNewLine = true
		}
	end

	Contents[ #Contents + 1 ] = MessageColour
	Contents[ #Contents + 1 ] = MessageText

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

local IsType = Shine.IsType
local Max = math.max
local StringExplode = string.Explode
local StringFormat = string.format
local StringSub = string.sub
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat
local TableCopy = table.Copy
local TableEmpty = table.Empty
local TableNew = require "table.new"
local TableRemove = table.remove
local type = type

local function GetMidPoint( Start, End )
	local Mid = End - Start
	return Start + ( Mid + Mid % 2 ) * 0.5
end

local function TextWrap( TextSizeProvider, Word, MaxWidth, Parts, StopAfter )
	local Chars = StringUTF8Encode( Word )
	local Start = 1
	local End = #Chars

	if End == 0 or ( StopAfter and Parts.Count >= StopAfter ) then
		return Parts
	end

	local Mid = GetMidPoint( Start, End )

	for i = 1, End do
		local TextBefore = TableConcat( Chars, "", 1, Mid - 1 )
		local TextAfter = TextBefore..Chars[ Mid ]

		local WidthBefore = TextSizeProvider:GetWidth( TextBefore )
		local WidthAfter = TextSizeProvider:GetWidth( TextAfter )

		if WidthAfter > MaxWidth and WidthBefore <= MaxWidth then
			-- Text must be wrapped here, wrap it then continue with the remaining text.
			Parts.Count = Parts.Count + 1
			Parts[ Parts.Count ] = TextBefore
			return TextWrap( TextSizeProvider, TableConcat( Chars, "", Mid ), MaxWidth, Parts, StopAfter )
		elseif WidthAfter > MaxWidth then
			if Mid == 1 then
				-- Even a single character is too wide, so we have to allow it to overflow,
				-- otherwise there'll never be an answer.
				Parts.Count = Parts.Count + 1
				Parts[ Parts.Count ] = TextAfter
				return TextWrap( TextSizeProvider, TableConcat( Chars, "", Mid + 1 ), MaxWidth, Parts, StopAfter )
			end
			-- Too far forward, look in the previous half.
			End = Mid - 1
			Mid = GetMidPoint( Start, End )
		elseif WidthAfter < MaxWidth then
			if Mid == #Chars then
				-- Text can't be advanced further, stop here.
				Parts.Count = Parts.Count + 1
				Parts[ Parts.Count ] = TextAfter
				return Parts
			end

			-- Too far back, look in the next half.
			Start = Mid + 1
			Mid = GetMidPoint( Start, End )
		elseif WidthAfter == MaxWidth then
			-- We've found a point where the text is exactly the right size, add it and continue wrapping if there's
			-- any left.
			Parts.Count = Parts.Count + 1
			Parts[ Parts.Count ] = TextAfter

			if Mid ~= #Chars then
				return TextWrap( TextSizeProvider, TableConcat( Chars, "", Mid + 1 ), MaxWidth, Parts, StopAfter )
			end

			return Parts
		end
	end

	return Parts
end

local ElementTypes = {}
local function DefineElementType( Name )
	local TypeDef = Shine.TypeDef()
	TypeDef.Type = Name
	TypeDef.GetLines = function() end

	ElementTypes[ Name ] = TypeDef

	return TypeDef
end

local SegmentWidthKeys = {
	[ true ] = "WidthWithoutSpace",
	[ false ] = "Width"
}

local function AddThinkFunction( Element, ExtraThink )
	-- Remove any old override (so Think comes from the metatable).
	Element.Think = nil

	if not ExtraThink then return end

	local OldThink = Element.Think
	function Element:Think( DeltaTime )
		ExtraThink( self, DeltaTime )
		return OldThink( self, DeltaTime )
	end
end

do
	local Text = DefineElementType( "Text" )
	function Text:Init( Text )
		if IsType( Text, "string" ) then
			self.Value = Text
		else
			self.Value = Text.Value
			self.Think = Text.Think
		end

		return self
	end

	function Text:GetLines()
		local ElementLines = StringExplode( self.Value, "\r?\n" )
		if #ElementLines == 1 then
			return { self }
		end

		for i = 1, #ElementLines do
			ElementLines[ i ] = Text( ElementLines[ i ] )
		end

		return ElementLines
	end

	local WrappedParts = TableNew( 3, 0 )
	local function EagerlyWrapText( Index, TextSizeProvider, Segments, MaxWidth, Word )
		TableEmpty( WrappedParts )

		-- Eagerly text-wrap here to make things easier when word-wrapping.
		WrappedParts.Count = 0
		TextWrap( TextSizeProvider, Word, MaxWidth, WrappedParts )

		for j = 1, WrappedParts.Count do
			local Width = TextSizeProvider:GetWidth( WrappedParts[ j ] )
			local Segment = Text( WrappedParts[ j ] )
			Segment.Width = Width
			Segment.WidthWithoutSpace = Width
			Segment.Height = TextSizeProvider.TextHeight
			Segment.OriginalElement = Index

			Segments[ #Segments + 1 ] = Segment
		end

		TableEmpty( WrappedParts )
	end

	local function AddSegmentFromWord( Index, TextSizeProvider, Segments, Word, Width, NoSpace )
		local Segment = Text( Word )
		Segment.Width = Width + ( NoSpace and 0 or TextSizeProvider.SpaceSize )
		Segment.WidthWithoutSpace = Width
		Segment.Height = TextSizeProvider.TextHeight
		Segment.OriginalElement = Index

		Segments[ #Segments + 1 ] = Segment
	end

	local function WrapUsingAnchor( Index, TextSizeProvider, Segments, MaxWidth, Word, XPos )
		-- Only bother to wrap against the anchor if there's enough room left on the line after it.
		local WidthRemaining = MaxWidth - XPos
		if WidthRemaining / MaxWidth <= 0.1 then return false end

		TableEmpty( WrappedParts )

		-- Wrap the first part of text to the remaining width and add it as a segment.
		WrappedParts.Count = 0
		TextWrap( TextSizeProvider, Word, WidthRemaining, WrappedParts, 1 )

		AddSegmentFromWord(
			Index, TextSizeProvider, Segments, WrappedParts[ 1 ], TextSizeProvider:GetWidth( WrappedParts[ 1 ] ), true
		)

		-- Now take the text that's left, and wrap it based on the full max width (as it's no longer on the same
		-- line as the anchor).
		local RemainingText = StringSub( Word, #WrappedParts[ 1 ] + 1 )
		local Width = TextSizeProvider:GetWidth( RemainingText )
		if Width > MaxWidth then
			EagerlyWrapText( Index, TextSizeProvider, Segments, MaxWidth, RemainingText )
		else
			AddSegmentFromWord( Index, TextSizeProvider, Segments, RemainingText, Width )
		end

		TableEmpty( WrappedParts )

		return true
	end

	function Text:Split( Index, TextSizeProvider, Segments, MaxWidth, XPos )
		local Words = StringExplode( self.Value, " ", true )
		for i = 1, #Words do
			local Word = Words[ i ]
			local Width = TextSizeProvider:GetWidth( Word )
			if Width > MaxWidth then
				-- Word will need text wrapping.
				-- First try to wrap starting at the last element's position.
				-- If there's not enough space left, treat the text as a new line.
				if not WrapUsingAnchor( Index, TextSizeProvider, Segments, MaxWidth, Word, XPos ) then
					EagerlyWrapText( Index, TextSizeProvider, Segments, MaxWidth, Word )
				end

				XPos = Segments[ #Segments ].WidthWithoutSpace + TextSizeProvider.SpaceSize
			else
				AddSegmentFromWord( Index, TextSizeProvider, Segments, Word, Width, i == 1 )
				XPos = XPos + Width + TextSizeProvider.SpaceSize
			end
		end
	end

	function Text:GetWidth( TextSizeProvider )
		local Width = TextSizeProvider:GetWidth( self.Value )
		return Width, Width
	end

	function Text:Merge( Segments, StartIndex, EndIndex )
		local Segment = TableCopy( self )

		local Width = 0
		local Height = Segments[ StartIndex ].Height

		local Words = TableNew( EndIndex - StartIndex + 1, 0 )
		for i = StartIndex, EndIndex do
			Width = Width + Segments[ i ][ SegmentWidthKeys[ i == StartIndex ] ]
			Words[ #Words + 1 ] = Segments[ i ].Value
		end

		Segment.Width = Width
		Segment.Height = Height
		Segment.Value = TableConcat( Words, " " )

		return Segment
	end

	function Text:MakeElement( Context )
		local Label = Context:MakeElement( "Label" )
		Label:SetIsSchemed( false )
		Label:SetFontScale( Context.CurrentFont, Context.CurrentScale )
		Label:SetColour( Context.CurrentColour )
		Label:SetText( self.Value )

		AddThinkFunction( Label, self.Think )

		Label.DoClick = Context.DoClick
		Label.DoRightClick = Context.DoRightClick

		-- We already computed the width/height values, so apply them now.
		Label.CachedTextWidth = self.Width
		Label.CachedTextHeight = self.Height

		return Label
	end

	function Text:__tostring()
		return StringFormat( "Text \"%s\" (Width = %s)", self.Value, self.Width )
	end
end

do
	-- Sets what happens when elements following this element are clicked.
	-- To reset, just provide an empty mouse input element.
	local MouseInput = DefineElementType( "MouseInput" )
	function MouseInput:Init( Params )
		self.DoClick = Params.DoClick
		self.DoRightClick = Params.DoRightClick
		return self
	end

	function MouseInput:Split()
		-- Element is not splittable.
	end

	function MouseInput:GetWidth()
		return 0, 0
	end

	function MouseInput:MakeElement( Context )
		Context.DoClick = self.DoClick
		Context.DoRightClick = self.DoRightClick
	end

	function MouseInput:__tostring()
		return StringFormat( "MouseInput (DoClick = %s, DoRightClick = %s)", self.DoClick, self.DoRightClick )
	end
end

do
	local Colour = DefineElementType( "Colour" )
	function Colour:Init( Value )
		self.Value = Value
		return self
	end

	function Colour:Split()
		-- Element is not splittable.
	end

	function Colour:GetWidth()
		return 0, 0
	end

	function Colour:MakeElement( Context )
		Context.CurrentColour = self.Value
	end

	function Colour:__tostring()
		return StringFormat( "Colour (%s, %s, %s, %s)", self.Value.r, self.Value.g, self.Value.b, self.Value.a )
	end
end

do
	local Font = DefineElementType( "Font" )
	function Font:Init( Font, Scale )
		self.Font = Font
		self.Scale = Scale
		return self
	end

	function Font:Split( Index, TextSizeProvider )
		TextSizeProvider:SetFontScale( self.Font, self.Scale )
	end

	function Font:GetWidth()
		return 0, 0
	end

	function Font:MakeElement( Context )
		Context.CurrentFont = self.Font
		Context.CurrentScale = self.Scale
	end

	function Font:__tostring()
		return StringFormat( "Font (%s with scale %s)", self.Font, self.Scale )
	end
end

do
	local Image = DefineElementType( "Image" )
	function Image:Init( Params )
		self.Texture = Params.Texture
		self.AbsoluteSize = Params.AbsoluteSize
		self.AutoSize = Params.AutoSize
		self.AspectRatio = Params.AspectRatio
		self.Think = Params.Think
		return self
	end

	function Image:ConfigureSize( TextSizeProvider, MaxWidth )
		self.Size = self.AbsoluteSize or self.AutoSize:GetValue(
			Vector2( MaxWidth, TextSizeProvider.TextHeight )
		)
		if self.AspectRatio then
			self.Size.x = self.Size.y * self.AspectRatio
		end
	end

	function Image:Split( Index, TextSizeProvider, Segments, MaxWidth )
		self.OriginalElement = Index
		self:ConfigureSize( TextSizeProvider, MaxWidth )
		self.Width = self.Size.x
		self.WidthWithoutSpace = self.Width

		Segments[ #Segments + 1 ] = self
	end

	function Image:GetWidth( TextSizeProvider, MaxWidth )
		self:ConfigureSize( TextSizeProvider, MaxWidth )
		return self.Size.x, self.Size.x
	end

	function Image:MakeElement( Context )
		local Image = Context:MakeElement( "Image" )
		Image:SetIsSchemed( false )
		Image:SetTexture( self.Texture )
		-- Size already computed from auto-size in wrapping step.
		Image:SetSize( self.Size )

		AddThinkFunction( Image, self.Think )

		Image.DoClick = Context.DoClick
		Image.DoRightClick = Context.DoRightClick

		return Image
	end

	function Image:__tostring()
		return StringFormat( "Image (Texture = %s, Size = %s)", self.Texture, self.Size )
	end
end

do
	local Spacer = DefineElementType( "Spacer" )
	function Spacer:Init( Params )
		self.AutoWidth = Params.AutoWidth
		self.IgnoreOnNewLine = Params.IgnoreOnNewLine
		return self
	end

	function Spacer:Split( Index, TextSizeProvider, Segments, MaxWidth )
		self.OriginalElement = Index
		self.Width = self.AutoWidth:GetValue( MaxWidth, 1 )
		self.WidthWithoutSpace = self.IgnoreOnNewLine and 0 or self.Width

		Segments[ #Segments + 1 ] = self
	end

	function Spacer:GetWidth( TextSizeProvider, MaxWidth )
		local Width = self.AutoWidth:GetValue( MaxWidth, 1 )
		return Width, self.IgnoreOnNewLine and 0 or Width
	end

	function Spacer:MakeElement( Context )
		if Context.CurrentIndex == 1 and self.IgnoreOnNewLine then
			return
		end

		Context.NextMargin = ( Context.NextMargin or 0 ) + self.Width
	end

	function Spacer:__tostring()
		return StringFormat( "Spacer (%s)", self.Width or self.AutoWidth )
	end
end

local ContentFactories = {
	string = ElementTypes.Text,
	cdata = ElementTypes.Colour,
	table = function( Value )
		local Type = Value.Type
		if not Type then return nil end

		local Factory = ElementTypes[ Type ]
		if not Factory then return nil end

		return Factory( Value )
	end
}

-- Parses a flat list of text/colours/elements into a list of lines, based on the line breaks
-- in each text element. These lines will be wrapped individually when the layout is computed.
function ChatLine:ParseContents( Contents, ShowTimestamp )
	local Lines = {}
	local Elements = TableNew( #Contents, 0 )

	if ShowTimestamp then
		Elements[ #Elements + 1 ] = ElementTypes.Colour( TimestampColour )
		Elements[ #Elements + 1 ] = ElementTypes.Text( OSDate( "%H:%M - " ) )
	end

	for i = 1, #Contents do
		local Value = Contents[ i ]
		local Type = type( Value )
		Elements[ #Elements + 1 ] = ContentFactories[ Type ] and ContentFactories[ Type ]( Value )

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

-- Merges word segments back into a single text segment (where they belong to the same original element),
-- and produces a final line that can be displayed.
local function ConsolidateSegments( Elements, Segments, StartIndex, EndIndex, LastElementIndex )
	local Line = TableNew( EndIndex - StartIndex + 1, 0 )
	local CurrentElementIndex = Segments[ StartIndex ].OriginalElement
	local LastElementChangeIndex = StartIndex

	for i = LastElementIndex, CurrentElementIndex - 1 do
		Line[ #Line + 1 ] = Elements[ i ]
	end

	for i = StartIndex, EndIndex do
		local Element = Segments[ i ]
		local Change = Element.OriginalElement - CurrentElementIndex

		if Change > 0 then
			local NumSegments = i - LastElementChangeIndex
			if NumSegments == 1 then
				-- Single element (one word, or not text at all)
				Line[ #Line + 1 ] = Segments[ i - 1 ]
			else
				-- Multiple words from the same element, need to be merged back together.
				Line[ #Line + 1 ] = Elements[ CurrentElementIndex ]:Merge( Segments, LastElementChangeIndex, i - 1 )
			end

			-- Copy over anything in between the wrapped segments (i.e. font or colour changes).
			for j = CurrentElementIndex + 1, Element.OriginalElement - 1 do
				Line[ #Line + 1 ] = Elements[ j ]
			end

			CurrentElementIndex = Element.OriginalElement
			LastElementChangeIndex = i
		end
	end

	-- Also add the final element.
	local NumSegments = EndIndex - LastElementChangeIndex + 1
	if NumSegments == 1 then
		Line[ #Line + 1 ] = Segments[ EndIndex ]
	else
		Line[ #Line + 1 ] = Elements[ CurrentElementIndex ]:Merge( Segments, LastElementChangeIndex, EndIndex )
	end

	return Line, CurrentElementIndex + 1
end

local Segments = TableNew( 50, 0 )
local function WrapLine( WrappedLines, TextSizeProvider, Line, MaxWidth )
	TableEmpty( Segments )

	local CurrentWidth = 0
	local StartIndex = 1
	local LastSegment = 0
	local LastElementIndex = 1
	local WrappingXPos

	for i = 1, #Line do
		local Element = Line[ i ]

		local Width, WidthWithoutSpace = Element:GetWidth( TextSizeProvider, MaxWidth )
		local RelevantWidth = #Segments + 1 == StartIndex and WidthWithoutSpace or Width
		if CurrentWidth + RelevantWidth < MaxWidth then
			-- No need to split the element as it fits entirely on the current line.
			Element.Width = Width
			Element.WidthWithoutSpace = WidthWithoutSpace
			Element.OriginalElement = i
			Segments[ #Segments + 1 ] = Element
		else
			Element:Split( i, TextSizeProvider, Segments, MaxWidth, CurrentWidth )
		end

		for j = LastSegment + 1, #Segments do
			CurrentWidth = CurrentWidth + Segments[ j ][ SegmentWidthKeys[ j == StartIndex ] ]
			if CurrentWidth > MaxWidth then
				-- If the first element is too big for a line, accept it anyway as any text
				-- will have been wrapped in segments already. Not accepting it would result in an empty line.
				local EndIndex = j == StartIndex and j or j - 1
				local Line, ElementIndex = ConsolidateSegments( Line, Segments, StartIndex, EndIndex, LastElementIndex )
				WrappedLines[ #WrappedLines + 1 ] = Line
				LastElementIndex = ElementIndex

				StartIndex = j
				CurrentWidth = Segments[ j ].WidthWithoutSpace
			end
		end

		LastSegment = #Segments
	end

	WrappedLines[ #WrappedLines + 1 ] = ConsolidateSegments( Line, Segments, StartIndex, #Segments, LastElementIndex )

	TableEmpty( Segments )

	return WrappedLines
end

function ChatLine:WrapLine( WrappedLines, Line, Context )
	local MaxWidth = Context.MaxWidth
	local TextSizeProvider = Context.TextSizeProvider
	return WrapLine( WrappedLines, TextSizeProvider, Line, MaxWidth )
end

local Label
local function GetLabel()
	if not Label then
		Label = SGUI:Create( "Label" )
		Label:SetIsSchemed( false )
		Label:SetIsVisible( false )
		GetLabel = function() return Label end
	end
	return Label
end

local TextSizeProvider = Shine.TypeDef()
function TextSizeProvider:Init( Font, Scale )
	self.WordSizeCache = TableNew( 0, 10 )
	self:SetFontScale( Font, Scale )

	return self
end

function TextSizeProvider:SetFontScale( Font, Scale )
	if Font == self.Font and Scale == self.Scale then return end

	local Label = GetLabel()

	self.Font = Font
	self.Scale = Scale
	Label:SetFontScale( Font, Scale )

	TableEmpty( self.WordSizeCache )

	self.SpaceSize = Label:GetTextWidth( " " )
	self.TextHeight = Label:GetTextHeight( "!" )
end

function TextSizeProvider:GetWidth( Text )
	local Size = self.WordSizeCache[ Text ]
	if not Size then
		Size = GetLabel():GetTextWidth( Text )
		self.WordSizeCache[ Text ] = Size
	end
	return Size
end

function ChatLine:PerformWrapping()
	local Lines = self.Lines
	local MaxWidth = self.MaxWidth
	if not MaxWidth or not Lines then return end

	local Start = Shared.GetSystemTimeReal()

	local WrappedLines = TableNew( #Lines, 0 )

	local TextSizeProvider = TextSizeProvider( self.Font, self.TextScale )
	local Context = {
		TextSizeProvider = TextSizeProvider,
		MaxWidth = MaxWidth
	}

	for i = 1, #Lines do
		self:WrapLine( WrappedLines, Lines[ i ], Context )
	end

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
		for j = 1, #Line do
			Context.CurrentIndex = j

			local Element = Line[ j ]

			local Control = Element:MakeElement( Context )
			if Control then
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
				LineHeight = Max( LineHeight, Size.y )
			end
		end

		Context.NextMargin = nil

		Parent = self
		MaxWidth = Max( MaxWidth, LineWidth )
		YOffset = YOffset + LineHeight + Spacing
	end

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
