--[[
	Text element for rich text.
]]

local IsType = Shine.IsType
local StringExplode = string.Explode
local StringFormat = string.format
local StringSub = string.sub
local TableConcat = table.concat
local TableCopy = table.Copy
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

	self.AddThinkFunction( Label, self.Think )

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

return Text
