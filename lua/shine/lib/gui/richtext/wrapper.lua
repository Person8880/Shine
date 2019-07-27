--[[
	Provides rich-text aware wrapping.
]]

local TextSizeProvider = require "shine/lib/gui/richtext/text_size_provider"

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

local function TextWrap( TextSizeProvider, Word, MaxWidth, Parts, StopAfter )
	local Chars = StringUTF8Encode( Word )
	local Start = 1
	local End = #Chars

	Parts.Count = Parts.Count or 0

	if End == 0 or ( StopAfter and Parts.Count >= StopAfter ) then
		return Parts
	end

	local Mid = GetMidPoint( Start, End )

	for i = 1, End do
		local TextBefore = TableConcat( Chars, "", 1, Mid - 1 )
		local TextAfter = TextBefore..Chars[ Mid ]

		local WidthBefore = TextSizeProvider:GetWidth( TextBefore )
		local WidthAfter = TextSizeProvider:GetWidth( TextAfter )

		if WidthAfter > MaxWidth and WidthBefore <= MaxWidth and #TextBefore > 0 then
			-- Text must be wrapped here, wrap it then continue with the remaining text.
			Parts.Count = Parts.Count + 1
			Parts[ Parts.Count ] = TextBefore
			return TextWrap( TextSizeProvider, TableConcat( Chars, "", Max( Mid, 2 ) ), MaxWidth, Parts, StopAfter )
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
				return TextWrap( TextSizeProvider, TableConcat( Chars, "", Max( Mid + 1, 2 ) ), MaxWidth, Parts, StopAfter )
			end

			return Parts
		end
	end

	return Parts
end
Wrapper.TextWrap = TextWrap

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
		if CurrentWidth + RelevantWidth <= MaxWidth then
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
			if CurrentWidth >= MaxWidth then
				-- If the first element is too big for a line, accept it anyway as any text
				-- will have been wrapped in segments already. Not accepting it would result in an empty line.
				local IsEndingOnCurrentElement = j == StartIndex or CurrentWidth == MaxWidth
				local EndIndex = IsEndingOnCurrentElement and j or j - 1
				local Line, ElementIndex = ConsolidateSegments( Line, Segments, StartIndex, EndIndex, LastElementIndex )
				WrappedLines[ #WrappedLines + 1 ] = Line
				LastElementIndex = ElementIndex

				StartIndex = IsEndingOnCurrentElement and ( j + 1 ) or j
				CurrentWidth = IsEndingOnCurrentElement and 0 or Segments[ j ].WidthWithoutSpace
			end
		end

		LastSegment = #Segments
	end

	if StartIndex <= #Segments then
		WrappedLines[ #WrappedLines + 1 ] = ConsolidateSegments( Line, Segments, StartIndex, #Segments, LastElementIndex )
	end

	TableEmpty( Segments )

	return WrappedLines
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

	for i = 1, #Lines do
		WrapLine( WrappedLines, TextSizeProvider, Lines[ i ], MaxWidth )
	end

	return WrappedLines
end

return Wrapper
