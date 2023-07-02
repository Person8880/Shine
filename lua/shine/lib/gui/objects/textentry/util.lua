--[[
	Shared utilities for text entry controls.
]]

local TextEntryUtil = {}

function TextEntryUtil.FindPreviousSpace( Characters, Length, Column )
	local PreviousSpace = 1
	for i = Column, 1, -1 do
		if Characters[ i ] == " " then
			PreviousSpace = i
			break
		end
	end
	return PreviousSpace
end

function TextEntryUtil.FindWordBoundsFromCharacters( Characters, Length, Column )
	local PreviousSpace = TextEntryUtil.FindPreviousSpace( Characters, Length, Column )
	local LastCharIndex = Length
	for i = Column + 1, Length do
		if Characters[ i ] == " " then
			LastCharIndex = i - 1
			break
		end
	end
	return PreviousSpace, LastCharIndex
end

return TextEntryUtil
