--[[
	Text element for rich text.
]]

local IsType = Shine.IsType
local StringExplode = string.Explode
local StringFormat = string.format
local StringSub = string.sub
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableNew = require "table.new"

local Wrapper = require "shine/lib/gui/richtext/wrapper"
local SegmentWidthKeys = Wrapper.SegmentWidthKeys
local TextWrap = Wrapper.TextWrap

local BaseElement = require "shine/lib/gui/richtext/elements/base"
local Text = Shine.TypeDef( BaseElement )

function Text:Init( Text )
	if IsType( Text, "string" ) then
		self.Value = Text
	else
		self.Value = Text.Value
		self.Think = Text.Think

		self.DoClick = Text.DoClick
		self.DoRightClick = Text.DoRightClick
		self.Setup = Text.Setup

		self.ComputeWidth = Text.ComputeWidth

		if self.ComputeWidth then
			self.GetWidth = self.ComputeWidth
		end
	end

	return self
end

function Text:GetLines()
	local ElementLines = StringExplode( self.Value, "\r?\n" )
	if #ElementLines == 1 then
		return { self }
	end

	for i = 1, #ElementLines do
		local LineText = ElementLines[ i ]

		local Line = self:Copy()
		Line.Value = LineText

		ElementLines[ i ] = Line
	end

	return ElementLines
end

function Text:IsVisibleElement()
	return self.Value ~= ""
end

local WrappedParts = TableNew( 3, 0 )
local function EagerlyWrapText( self, Index, TextSizeProvider, Segments, MaxWidth, Word )
	TableEmpty( WrappedParts )

	-- Eagerly text-wrap here to make things easier when word-wrapping.
	WrappedParts.Count = 0
	TextWrap( TextSizeProvider, Word, MaxWidth, WrappedParts )

	for j = 1, WrappedParts.Count do
		local WrappedText = WrappedParts[ j ]
		local Width = TextSizeProvider:GetWidth( WrappedText )
		local Segment = Text( self )
		Segment.Value = WrappedText
		Segment.Width = Width
		Segment.WidthWithoutSpace = Width
		Segment.Height = TextSizeProvider.TextHeight
		Segment.OriginalElement = Index

		Segments[ #Segments + 1 ] = Segment
	end

	TableEmpty( WrappedParts )
end

local function AddSegmentFromWord( self, Index, TextSizeProvider, Segments, Word, Width, SpaceWidth )
	local Segment = Text( self )
	Segment.Value = Word
	Segment.Width = Width + SpaceWidth
	Segment.WidthWithoutSpace = Width
	Segment.Height = TextSizeProvider.TextHeight
	Segment.OriginalElement = Index

	Segments[ #Segments + 1 ] = Segment
end

local function WrapUsingAnchor( self, Index, TextSizeProvider, Segments, MaxWidth, Word, XPos )
	-- Only bother to wrap against the anchor if there's enough room left on the line after it.
	local WidthRemaining = MaxWidth - XPos
	if WidthRemaining / MaxWidth <= 0.1 then return false end

	TableEmpty( WrappedParts )

	-- Wrap the first part of text to the remaining width and add it as a segment.
	WrappedParts.Count = 0
	TextWrap( TextSizeProvider, Word, WidthRemaining, WrappedParts, 1 )

	AddSegmentFromWord(
		self, Index, TextSizeProvider, Segments, WrappedParts[ 1 ], TextSizeProvider:GetWidth( WrappedParts[ 1 ] ), 0
	)

	-- Now take the text that's left, and wrap it based on the full max width (as it's no longer on the same
	-- line as the anchor).
	local RemainingText = StringSub( Word, #WrappedParts[ 1 ] + 1 )
	local Width = TextSizeProvider:GetWidth( RemainingText )
	if Width > MaxWidth then
		EagerlyWrapText( self, Index, TextSizeProvider, Segments, MaxWidth, RemainingText )
	else
		AddSegmentFromWord( self, Index, TextSizeProvider, Segments, RemainingText, Width, 0 )
	end

	TableEmpty( WrappedParts )

	return true
end

-- First word is a special case. If it needs text wrapping, it needs to wrap based on the current x-offset.
local function WrapFirstWord( self, Index, TextSizeProvider, Segments, MaxWidth, XPos, Word )
	local Width = TextSizeProvider:GetWidth( Word )
	local WidthToCompareAgainst = MaxWidth - XPos

	if Width > WidthToCompareAgainst then
		if not WrapUsingAnchor( self, Index, TextSizeProvider, Segments, MaxWidth, Word, XPos ) then
			EagerlyWrapText( self, Index, TextSizeProvider, Segments, MaxWidth, Word )
		end
	else
		AddSegmentFromWord( self, Index, TextSizeProvider, Segments, Word, Width, 0 )
	end
end

function Text:Split( Index, TextSizeProvider, Segments, MaxWidth, XPos )
	local Words = StringExplode( self.Value, " ", true )

	WrapFirstWord( self, Index, TextSizeProvider, Segments, MaxWidth, XPos, Words[ 1 ] )

	local SpaceWidth = TextSizeProvider.SpaceSize
	for i = 2, #Words do
		local Word = Words[ i ]
		local Width = TextSizeProvider:GetWidth( Word )
		if Width > MaxWidth then
			-- Word will need text wrapping.
			EagerlyWrapText( self, Index, TextSizeProvider, Segments, MaxWidth, Word )
		else
			AddSegmentFromWord( self, Index, TextSizeProvider, Segments, Word, Width, SpaceWidth )
		end
	end
end

function Text:GetWidth( TextSizeProvider )
	local Width = TextSizeProvider:GetWidth( self.Value )
	return Width, Width
end

function Text:Merge( Segments, StartIndex, EndIndex )
	local Segment = Text( self )

	local Width = 0
	local Height = Segments[ StartIndex ].Height

	local Words = TableNew( EndIndex - StartIndex + 1, 0 )
	local WordIndex = 0
	for i = StartIndex, EndIndex do
		Width = Width + Segments[ i ][ SegmentWidthKeys[ i == StartIndex ] ]
		WordIndex = WordIndex + 1
		Words[ WordIndex ] = Segments[ i ].Value
	end

	Segment.Width = Width
	Segment.Height = Height
	Segment.Value = TableConcat( Words, " " )

	return Segment
end

function Text:MakeElement( Context )
	local Label = Context.MakeElement( "Label" )
	Label:SetIsSchemed( false )
	Label:SetFontScale( Context.CurrentFont, Context.CurrentScale )
	Label:SetColour( Context.CurrentColour )
	Label:SetShadow( Context.CurrentTextShadow )
	Label:SetText( self.Value )

	self.AddThinkFunction( Label, self.Think )

	Label.DoClick = self.DoClick
	Label.DoRightClick = self.DoRightClick

	-- We already computed the width/height values, so apply them now.
	Label.CachedTextWidth = self.Width
	Label.CachedTextHeight = self.Height

	self:Setup( Label )

	return Label
end

function Text:Copy()
	return Text( self )
end

function Text:__tostring()
	return StringFormat( "Text \"%s\" (Width = %s)", self.Value, self.Width )
end

return Text
