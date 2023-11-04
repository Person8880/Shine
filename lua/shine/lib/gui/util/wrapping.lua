--[[
	Text wrapping utilities.
]]

local IsApproximatelyGreaterEqual = Shine.GUI.IsApproximatelyGreaterEqual
local Max = math.max
local StringFormat = string.format
local StringIterateExploded = string.IterateExploded
local StringSub = string.sub
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableNew = require "table.new"

local Wrapping = {}

--[[
	Wraps text to fit the size limit. Used for long words...

	Returns two strings, first one fits entirely on one line, the other may not, and should be
	added to the next word.
]]
local function TextWrap( Label, Text, XPos, MaxWidth )
	local FirstLine = Text
	local SecondLine = ""
	local Chars, Length = StringUTF8Encode( Text )
	local Width = 0

	-- Character by character, extend the text until it exceeds the width limit.
	for i = 1, Length do
		Width = Width + Label:GetTextWidth( Chars[ i ] )

		-- Once it reaches the limit, we go back a character, and set our first and second line results.
		if not IsApproximatelyGreaterEqual( MaxWidth, XPos + Width ) then
			-- The max makes sure we're cutting at least one character out of the text,
			-- to avoid an infinite loop.
			FirstLine = TableConcat( Chars, "", 1, Max( i - 1, 1 ) )
			SecondLine = TableConcat( Chars, "", Max( i, 2 ), Length )
			break
		end
	end

	return FirstLine, SecondLine
end
Wrapping.TextWrap = TextWrap

local Lines = TableNew( 25, 0 )
local LineCount = 0

local function WordWrapLine( Label, Line, SpaceWidth, XPos, MaxWidth, MaxLines )
	local Width = 0
	local i = 0
	local StartIndex = 1

	for EndIndex, Word in StringIterateExploded( Line, " ", true ) do
		::Start::

		Width = Width + Label:GetTextWidth( Word )

		local CurrentSpaceWidth = i * SpaceWidth

		if not IsApproximatelyGreaterEqual( MaxWidth, XPos + Width + CurrentSpaceWidth ) then
			-- This means one word is wider than the allowed space, so we need to cut it part way through.
			if i == 0 then
				local FirstLine, SecondLine = TextWrap( Label, Word, XPos, MaxWidth )

				LineCount = LineCount + 1
				Lines[ LineCount ] = FirstLine

				if MaxLines and LineCount >= MaxLines then
					if EndIndex <= #Line then
						SecondLine = StringFormat( "%s %s", SecondLine, StringSub( Line, EndIndex + 1 ) )
					end
					return SecondLine
				end

				-- Rewind back to the start of this iteration, now considering only the second half of the word.
				Word = SecondLine
				StartIndex = EndIndex - #Word
				Width = 0
				i = 0

				goto Start
			end

			local PreviousEndIndex = EndIndex - #Word - 2

			LineCount = LineCount + 1
			Lines[ LineCount ] = StringSub( Line, StartIndex, PreviousEndIndex )

			StartIndex = PreviousEndIndex + 2

			if MaxLines and LineCount >= MaxLines then
				return StringSub( Line, StartIndex )
			end

			-- Rewind back to the start of this iteration, now considering the current word as the first word of a new
			-- line.
			i = 0
			Width = 0

			goto Start
		end

		i = i + 1
	end

	LineCount = LineCount + 1
	Lines[ LineCount ] = StringSub( Line, StartIndex )

	return ( MaxLines and LineCount >= MaxLines and "" ) or nil
end

--[[
	Word wraps text, adding new lines where the text exceeds the width limit.

	This time, it shouldn't freeze the game...
]]
function Wrapping.WordWrap( Label, Text, XPos, MaxWidth, MaxLines )
	LineCount = 0

	local SpaceWidth = Label:GetTextWidth( " " )
	local RemainingText

	for EndIndex, Line in StringIterateExploded( Text, "\n", true ) do
		local RemainingTextOnLine = WordWrapLine(
			Label,
			Line,
			SpaceWidth,
			XPos,
			MaxWidth,
			MaxLines
		)
		if RemainingTextOnLine then
			RemainingText = RemainingTextOnLine..StringSub( Text, EndIndex + 1 )
			break
		end
	end

	Label:SetText( TableConcat( Lines, "\n", 1, LineCount ) )
	TableEmpty( Lines )

	return RemainingText
end

return Wrapping
