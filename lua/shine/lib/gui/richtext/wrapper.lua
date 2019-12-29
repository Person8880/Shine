--[[
	Provides rich-text aware wrapping.
]]

local TextSizeProvider = require "shine/lib/gui/richtext/text_size_provider"

local Huge = math.huge
local Max = math.max
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableNew = require "table.new"

local SegmentWidthKeys = {
	[ true ] = "WidthWithoutSpace",
	[ false ] = "Width"
}

local Wrapper = {}
Wrapper.SegmentWidthKeys = SegmentWidthKeys

local function GetMidPoint( Start, End )
	local Mid = End - Start
	return Start + ( Mid + Mid % 2 ) * 0.5
end

local function TextWrapFromChars( TextSizeProvider, Chars, Start, End, MaxWidth, Parts, StopAfter )
	if End == 0 or Start > End or Parts.Count >= StopAfter then
		return Parts
	end

	local StartIndex = Start
	local EndIndex = End
	local Mid = GetMidPoint( Start, End )

	for i = 1, End do
		local TextBefore = TableConcat( Chars, "", StartIndex, Mid - 1 )
		local TextAfter = TextBefore..Chars[ Mid ]

		local WidthBefore = TextSizeProvider:GetWidth( TextBefore )
		local WidthAfter = TextSizeProvider:GetWidth( TextAfter )

		if WidthAfter > MaxWidth and WidthBefore <= MaxWidth and #TextBefore > 0 then
			-- Text must be wrapped here, wrap it then continue with the remaining text.
			Parts.Count = Parts.Count + 1
			Parts[ Parts.Count ] = TextBefore
			return TextWrapFromChars( TextSizeProvider, Chars, Max( Mid, 2 ), EndIndex, MaxWidth, Parts, StopAfter )
		elseif WidthAfter > MaxWidth then
			if Mid == StartIndex then
				-- Even a single character is too wide, so we have to allow it to overflow,
				-- otherwise there'll never be an answer.
				Parts.Count = Parts.Count + 1
				Parts[ Parts.Count ] = TextAfter
				return TextWrapFromChars( TextSizeProvider, Chars, Mid + 1, EndIndex, MaxWidth, Parts, StopAfter )
			end
			-- Too far forward, look in the previous half.
			End = Mid - 1
			Mid = GetMidPoint( Start, End )
		elseif WidthAfter < MaxWidth then
			if Mid == EndIndex then
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

			if Mid ~= EndIndex then
				return TextWrapFromChars( TextSizeProvider, Chars, Max( Mid + 1, 2 ), EndIndex, MaxWidth, Parts, StopAfter )
			end

			return Parts
		end
	end

	return Parts
end

local function TextWrap( TextSizeProvider, Word, MaxWidth, Parts, StopAfter )
	local Chars = StringUTF8Encode( Word )
	local Start = 1
	local End = #Chars
	return TextWrapFromChars( TextSizeProvider, Chars, Start, End, MaxWidth, Parts, StopAfter or Huge )
end
Wrapper.TextWrap = TextWrap

-- Merges word segments back into a single text segment (where they belong to the same original element),
-- and produces a final line that can be displayed.
local function ConsolidateSegments( Elements, Segments, StartIndex, EndIndex, LastElementIndex )
	local Line = TableNew( EndIndex - StartIndex + 1, 0 )
	local Index = 0
	local CurrentElementIndex = Segments[ StartIndex ].OriginalElement
	local LastElementChangeIndex = StartIndex

	for i = LastElementIndex, CurrentElementIndex - 1 do
		Index = Index + 1
		Line[ Index ] = Elements[ i ]
	end

	for i = StartIndex, EndIndex do
		local Element = Segments[ i ]
		local Change = Element.OriginalElement - CurrentElementIndex

		if Change > 0 then
			local NumSegments = i - LastElementChangeIndex

			Index = Index + 1

			if NumSegments == 1 then
				-- Single element (one word, or not text at all)
				Line[ Index ] = Segments[ i - 1 ]
			else
				-- Multiple words from the same element, need to be merged back together.
				Line[ Index ] = Elements[ CurrentElementIndex ]:Merge( Segments, LastElementChangeIndex, i - 1 )
			end

			-- Copy over anything in between the wrapped segments (i.e. font or colour changes).
			for j = CurrentElementIndex + 1, Element.OriginalElement - 1 do
				Index = Index + 1
				Line[ Index ] = Elements[ j ]
			end

			CurrentElementIndex = Element.OriginalElement
			LastElementChangeIndex = i
		end
	end

	Index = Index + 1

	-- Also add the final element.
	local NumSegments = EndIndex - LastElementChangeIndex + 1
	if NumSegments == 1 then
		Line[ Index ] = Segments[ EndIndex ]
	else
		Line[ Index ] = Elements[ CurrentElementIndex ]:Merge( Segments, LastElementChangeIndex, EndIndex )
	end

	return Line, CurrentElementIndex + 1
end

local Segments = TableNew( 50, 0 )
local function WrapLine( WrappedLines, TextSizeProvider, Line, MaxWidth, NumLines )
	TableEmpty( Segments )

	local SegmentIndex = 0
	local CurrentWidth = 0
	local StartIndex = 1
	local LastSegment = 0
	local LastElementIndex = 1
	local WrappingXPos

	for i = 1, #Line do
		local Element = Line[ i ]

		local Width, WidthWithoutSpace = Element:GetWidth( TextSizeProvider, MaxWidth )
		local RelevantWidth = SegmentIndex + 1 == StartIndex and WidthWithoutSpace or Width
		if CurrentWidth + RelevantWidth <= MaxWidth then
			-- No need to split the element as it fits entirely on the current line.
			Element.Width = Width
			Element.WidthWithoutSpace = WidthWithoutSpace
			Element.OriginalElement = i

			SegmentIndex = SegmentIndex + 1
			Segments[ SegmentIndex ] = Element
		else
			Element:Split( i, TextSizeProvider, Segments, MaxWidth, CurrentWidth )
			SegmentIndex = #Segments
		end

		for j = LastSegment + 1, SegmentIndex do
			CurrentWidth = CurrentWidth + Segments[ j ][ SegmentWidthKeys[ j == StartIndex ] ]
			if CurrentWidth >= MaxWidth then
				-- If the first element is too big for a line, accept it anyway as any text
				-- will have been wrapped in segments already. Not accepting it would result in an empty line.
				local IsEndingOnCurrentElement = j == StartIndex or CurrentWidth == MaxWidth
				local EndIndex = IsEndingOnCurrentElement and j or j - 1
				local WrappedLine, ElementIndex = ConsolidateSegments(
					Line, Segments, StartIndex, EndIndex, LastElementIndex
				)

				NumLines = NumLines + 1
				WrappedLines[ NumLines ] = WrappedLine
				LastElementIndex = ElementIndex

				StartIndex = IsEndingOnCurrentElement and ( j + 1 ) or j
				CurrentWidth = IsEndingOnCurrentElement and 0 or Segments[ j ].WidthWithoutSpace
			end
		end

		LastSegment = SegmentIndex
	end

	if StartIndex <= SegmentIndex then
		NumLines = NumLines + 1
		WrappedLines[ NumLines ] = ConsolidateSegments( Line, Segments, StartIndex, SegmentIndex, LastElementIndex )
	end

	TableEmpty( Segments )

	return NumLines
end

function Wrapper.WordWrapRichTextLines( Options )
	local Lines = Options.Lines
	local MaxWidth = Options.MaxWidth
	local WrappedLines = TableNew( #Lines, 0 )

	local TextSizeProvider = Options.TextSizeProvider or TextSizeProvider( Options.Font, Options.TextScale )
	local Context = {
		TextSizeProvider = TextSizeProvider,
		MaxWidth = MaxWidth
	}

	local NumLines = 0
	for i = 1, #Lines do
		NumLines = WrapLine( WrappedLines, TextSizeProvider, Lines[ i ], MaxWidth, NumLines )
	end

	return WrappedLines
end

return Wrapper
