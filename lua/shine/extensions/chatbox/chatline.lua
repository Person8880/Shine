--[[
	Chat line object for the chatbox.
]]

local SGUI = Shine.GUI

local ChatLine = {}
local BackgroundColour = Colour( 0, 0, 0, 0 )

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

function ChatLine:SetMessage( Tags, PreColour, Prefix, MessageColour, MessageText )
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
			AutoWidth = self.PreMargin
		}
		-- When a prefix is present, wrap the message text starting from after it, rather than
		-- moving it to a new line if it exceeds the size limit with a single word.
		Contents[ #Contents + 1 ] = {
			Type = "WrappingAnchor"
		}
	end

	Contents[ #Contents + 1 ] = MessageColour
	Contents[ #Contents + 1 ] = MessageText

	self:SetContent( Contents )
end

function ChatLine:PerformLayout()
	if not self.ComputedWrapping then
		self:PerformWrapping()
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

local Max = math.max
local StringExplode = string.Explode
local StringFormat = string.format
local StringSub = string.sub
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat
local TableCopy = table.Copy
local TableEmpty = table.Empty
local TableNew = require "table.new"
local type = type

local function GetMidPoint( Start, End )
	local Mid = End - Start
	return Start + ( Mid + Mid % 2 ) * 0.5
end

local function TextWrap( TextSizeProvider, Word, MaxWidth, Parts, StopAfter )
	local Chars = StringUTF8Encode( Word )
	local Start = 1
	local End = #Chars

	if End == 0 then return Parts end

	if StopAfter and #Parts >= StopAfter then
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
			Parts[ #Parts + 1 ] = TextBefore
			return TextWrap( TextSizeProvider, TableConcat( Chars, "", Mid ), MaxWidth, Parts, StopAfter )
		elseif WidthAfter > MaxWidth then
			-- Too far forward, look in the previous half.
			End = Mid - 1
			Mid = GetMidPoint( Start, End )
		elseif WidthAfter < MaxWidth then
			if Mid == #Chars then
				-- Text can't be advanced further, stop here.
				Parts[ #Parts + 1 ] = TextAfter
				return Parts
			end

			-- Too far back, look in the next half.
			Start = Mid + 1
			Mid = GetMidPoint( Start, End )
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

do
	local Text = DefineElementType( "Text" )
	function Text:Init( Text )
		self.Value = Text
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

	local function EagerlyWrapText( Index, TextSizeProvider, Segments, MaxWidth, Word )
		-- Eagerly text-wrap here to make things easier when word-wrapping.
		local WrappedParts = TextWrap( TextSizeProvider, Word, MaxWidth, {} )
		for j = 1, #WrappedParts do
			local Width = TextSizeProvider:GetWidth( WrappedParts[ j ] )
			local Segment = Text( WrappedParts[ j ] )
			Segment.Width = Width
			Segment.WidthWithoutSpace = Width
			Segment.OriginalElement = Index

			Segments[ #Segments + 1 ] = Segment
		end
	end

	local function AddSegmentFromWord( Index, TextSizeProvider, Segments, Word, Width, NoSpace )
		local Segment = Text( Word )
		Segment.Width = Width + ( NoSpace and 0 or TextSizeProvider.SpaceSize )
		Segment.WidthWithoutSpace = Width
		Segment.OriginalElement = Index

		Segments[ #Segments + 1 ] = Segment
	end

	local function WrapUsingAnchor( Index, TextSizeProvider, Segments, MaxWidth, Word )
		-- Want to text wrap starting from the previous element's width, so work out
		-- how much space we have left from it and wrap accordingly.
		local WidthUsedSoFar = 0
		for i = 1, #Segments do
			WidthUsedSoFar = WidthUsedSoFar + ( i == 1 and Segments[ i ].WidthWithoutSpace or Segments[ i ].Width )
		end

		-- If the text before will go onto a new line already, find how far along it will be on whatever line
		-- it ends up on.
		WidthUsedSoFar = WidthUsedSoFar % MaxWidth

		-- Only bother to wrap against the anchor if there's enough room left on the line after it.
		local WidthRemaining = MaxWidth - WidthUsedSoFar
		if WidthRemaining / MaxWidth <= 0.1 then return false end

		-- Wrap the first part of text to the remaining width and add it as a segment.
		local Parts = TextWrap( TextSizeProvider, Word, WidthRemaining, {}, 1 )
		AddSegmentFromWord( Index, TextSizeProvider, Segments, Parts[ 1 ], TextSizeProvider:GetWidth( Parts[ 1 ] ), true )

		-- Now take the text that's left, and wrap it based on the full max width (as it's no longer on the same
		-- line as the anchor).
		local RemainingText = StringSub( Word, #Parts[ 1 ] + 1 )
		local Width = TextSizeProvider:GetWidth( RemainingText )
		if Width > MaxWidth then
			EagerlyWrapText( Index, TextSizeProvider, Segments, MaxWidth, RemainingText )
		else
			AddSegmentFromWord( Index, TextSizeProvider, Segments, RemainingText, Width )
		end

		return true
	end

	function Text:Split( TextSizeProvider, Segments, MaxWidth, Elements, CurrentIndex )
		local HasWrappingAnchor = false
		for i = CurrentIndex - 1, 1, -1 do
			local Element = Elements[ i ]
			if Element.Type == "WrappingAnchor" then
				HasWrappingAnchor = true
				break
			end

			if Element.Type == "Text" then
				-- More text behind us, that's already handled any anchor that's present.
				break
			end
		end

		local Words = StringExplode( self.Value, " ", true )
		for i = 1, #Words do
			local Word = Words[ i ]
			local Width = TextSizeProvider:GetWidth( Word )
			if Width > MaxWidth then
				-- Word will need text wrapping.
				-- Check if there's a wrapping anchor behind this element. If so, the desired behaviour is
				-- to text wrap starting from the anchor's position, rather than to move the word onto a new line.
				if not (
					i == 1 and HasWrappingAnchor and
					WrapUsingAnchor( self.Index, TextSizeProvider, Segments, MaxWidth, Word )
				) then
					EagerlyWrapText( self.Index, TextSizeProvider, Segments, MaxWidth, Word )
				end
			else
				AddSegmentFromWord( self.Index, TextSizeProvider, Segments, Word, Width, i == 1 )
			end
		end
	end

	function Text:Merge( Segments, StartIndex, EndIndex )
		local Segment = TableCopy( self )

		local Words = TableNew( EndIndex - StartIndex + 1, 0 )
		for i = StartIndex, EndIndex do
			Words[ #Words + 1 ] = Segments[ i ].Value
		end

		Segment.Value = TableConcat( Words, " " )

		return Segment
	end

	function Text:MakeElement( Context )
		local Label = SGUI:Create( "Label" )
		Label:SetIsSchemed( false )
		Label:SetFontScale( Context.CurrentFont, Context.CurrentScale )
		Label:SetColour( Context.CurrentColour )
		Label:SetText( self.Value )
		return Label
	end

	function Text:__tostring()
		return StringFormat( "Text \"%s\" (Width = %s)", self.Value, self.Width )
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

	function Font:Split( TextSizeProvider )
		TextSizeProvider:SetFontScale( self.Font, self.Scale )
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
		return self
	end

	function Image:Split( TextSizeProvider, Segments, MaxWidth )
		self.OriginalElement = self.Index
		self.Size = self.AbsoluteSize or self.AutoSize:GetValue(
			Vector2( MaxWidth, TextSizeProvider.TextHeight )
		)
		self.Width = self.Size.x
		self.WidthWithoutSpace = self.Width

		Segments[ #Segments + 1 ] = self
	end

	function Image:MakeElement( Context )
		local Image = SGUI:Create( "Image" )
		Image:SetIsSchemed( false )
		Image:SetTexture( self.Texture )
		-- Size already computed from auto-size in wrapping step.
		Image:SetSize( self.Size )
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
		return self
	end

	function Spacer:Split( TextSizeProvider, Segments, MaxWidth )
		self.OriginalElement = self.Index
		self.Width = self.AutoWidth:GetValue( MaxWidth, 1 )
		self.WidthWithoutSpace = self.Width

		Segments[ #Segments + 1 ] = self
	end

	function Spacer:MakeElement( Context )
		Context.NextMargin = self.Width
	end

	function Spacer:__tostring()
		return StringFormat( "Spacer (%s)", self.Width or self.AutoWidth )
	end
end

do
	local WrappingAnchor = DefineElementType( "WrappingAnchor" )
	function WrappingAnchor:Init()
		return self
	end

	function WrappingAnchor:Split()
		-- Element is not splittable.
	end

	function WrappingAnchor:MakeElement()
		-- Nothing to do, purely a hint to the wrapping system.
	end

	function WrappingAnchor:__tostring()
		return "WrappingAnchor"
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
function ChatLine:ParseContents( Contents )
	local Lines = {}
	local Elements = TableNew( #Contents, 0 )

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

function ChatLine:SetContent( Contents )
	self.Lines = self:ParseContents( Contents )
	self.ComputedWrapping = false
	self:InvalidateLayout()
end

local function SplitLineIntoSegments( TextSizeProvider, Line, MaxWidth )
	local Segments = {}

	for i = 1, #Line do
		Line[ i ].Index = i
		Line[ i ]:Split( TextSizeProvider, Segments, MaxWidth, Line, i )
	end

	return Segments
end

local function MergeTextSegments( Element, Segments, StartIndex, EndIndex )
	local Segment = TableCopy( Element )

	local Words = TableNew( EndIndex - StartIndex + 1, 0 )
	for i = StartIndex, EndIndex do
		Words[ #Words + 1 ] = Segments[ i ].Value
	end

	Segment.Value = TableConcat( Words, " " )

	return Segment
end

-- Merges word segments back into a single text segment (where they belong to the same original element),
-- and produces a final line that can be displayed.
local function ConsolidateSegments( Elements, Segments, StartIndex, EndIndex )
	local Line = {}
	local CurrentElementIndex = Segments[ StartIndex ].OriginalElement
	local LastElementChangeIndex = StartIndex

	if StartIndex == 1 then
		for i = 1, CurrentElementIndex - 1 do
			Line[ #Line + 1 ] = Elements[ i ]
		end
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

	return Line
end

function ChatLine:WrapLine( WrappedLines, Line, Context )
	local MaxWidth = Context.MaxWidth
	local TextSizeProvider = Context.TextSizeProvider

	local Segments = SplitLineIntoSegments( TextSizeProvider, Line, MaxWidth )
	local Start = 1
	local End = #Segments

	local PartitionStart = Start
	local PartitionEnd = End
	local Mid = GetMidPoint( PartitionStart, PartitionEnd )

	-- Perform a binary search over the words to apply wrapping in O(log(n)) time.
	-- At most the segments need splitting n times (as we guarantee that each segment is at most the max width
	-- or otherwise is not wrappable when splitting above).
	for i = 1, End do
		local SegmentBefore = Segments[ Mid - 1 ]
		local SegmentAfter = Segments[ Mid ]

		local WidthBefore = 0
		for i = Start, Mid - 1 do
			WidthBefore = WidthBefore + ( i == Start and Segments[ i ].WidthWithoutSpace or Segments[ i ].Width )
		end

		local WidthAfter = WidthBefore + SegmentAfter.Width
		if WidthAfter > MaxWidth and WidthBefore <= MaxWidth then
			-- If the width is transitioning from less than to greater than the max,
			-- this is a point at which the text must be wrapped.
			WrappedLines[ #WrappedLines + 1 ] = ConsolidateSegments( Line, Segments, Start, Mid - 1 )

			-- Then start the binary search again, this time with the start at the mid-point.
			Start = Mid
			PartitionStart = Start
			PartitionEnd = End
			Mid = GetMidPoint( PartitionStart, PartitionEnd )
		elseif WidthAfter > MaxWidth then
			-- Current half is too far ahead of the wrapping point, go backwards.
			PartitionEnd = Mid - 1
			Mid = GetMidPoint( PartitionStart, PartitionEnd )
		else
			if Mid == #Segments then
				-- Can't go any further forwards, stop.
				WrappedLines[ #WrappedLines + 1 ] = ConsolidateSegments( Line, Segments, Start, Mid )
				break
			end
			-- Current half is too far behind the wrapping point, go forwards.
			PartitionStart = Mid + 1
			Mid = GetMidPoint( PartitionStart, PartitionEnd )
		end
	end
end

local TextSizeProvider = Shine.TypeDef()
function TextSizeProvider:Init( Font, Scale )
	self.Label = SGUI:Create( "Label" )
	self.Label:SetIsSchemed( false )

	self.WordSizeCache = TableNew( 0, 10 )
	self:SetFontScale( Font, Scale )

	return self
end

function TextSizeProvider:SetFontScale( Font, Scale )
	if Font == self.Font and Scale == self.Scale then return end

	self.Font = Font
	self.Scale = Scale
	self.Label:SetFontScale( Font, Scale )

	TableEmpty( self.WordSizeCache )

	self.SpaceSize = self.Label:GetTextWidth( " " )
	self.TextHeight = self.Label:GetTextHeight( "!" )
end

function TextSizeProvider:GetWidth( Text )
	local Size = self.WordSizeCache[ Text ]
	if not Size then
		Size = self.Label:GetTextWidth( Text )
		self.WordSizeCache[ Text ] = Size
	end
	return Size
end

function TextSizeProvider:Destroy()
	self.Label:Destroy()
end

function ChatLine:PerformWrapping()
	local Lines = self.Lines
	local MaxWidth = self.MaxWidth
	if not MaxWidth or not Lines then return end

	local WrappedLines = TableNew( #Lines, 0 )

	local TextSizeProvider = TextSizeProvider( self.Font, self.TextScale )
	local Context = {
		TextSizeProvider = TextSizeProvider,
		MaxWidth = MaxWidth
	}

	for i = 1, #Lines do
		self:WrapLine( WrappedLines, Lines[ i ], Context )
	end

	TextSizeProvider:Destroy()

	self:ApplyLines( WrappedLines )
	self.ComputedWrapping = true
end

function ChatLine:ApplyLines( Lines )
	-- TODO: Possibly re-use children?
	if self.Children then
		for Child in self.Children:IterateBackwards() do
			Child:Destroy()
		end
	end

	local Context = {
		CurrentFont = self.Font,
		CurrentScale = self.TextScale,
		CurrentColour = Colour( 1, 1, 1, 1 )
	}

	local Parent = self
	local YOffset = 0
	local MaxWidth = 0
	local Spacing = self.LineSpacing:GetValue()

	for i = 1, #Lines do
		local Line = Lines[ i ]

		local RootControl
		local LineWidth = 0
		local LineHeight = 0
		for j = 1, #Line do
			local Element = Line[ j ]
			local Control = Element:MakeElement( Context )
			if Control then
				Control:SetParent( self, Parent.Background )
				if Parent ~= self then
					-- Make each element start from where the previous one ends.
					Control:SetAnchor( "TopRight" )
					Control:SetInheritsParentAlpha( true )

					if Context.NextMargin then
						Control:SetPos( Vector2( Context.NextMargin, 0 ) )
						Context.NextMargin = nil
					end
				else
					Control:SetPos( Vector2( 0, YOffset ) )
				end

				Parent = Control

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
end

SGUI:Register( "ChatLine", ChatLine )
