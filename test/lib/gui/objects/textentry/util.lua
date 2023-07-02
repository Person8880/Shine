--[[
	Text entry utilities tests.
]]

local TextEntryUtil = require "shine/lib/gui/objects/textentry/util"

local UnitTest = Shine.UnitTest
local Characters = { "t", "e", "s", "t", " ", "1", "2", "3", " ", "a", "b", "c" }
local Length = #Characters

UnitTest:Test( "FindPreviousSpace - Finds the first space behind the given position", function( Assert )
	local PrevSpace = TextEntryUtil.FindPreviousSpace( Characters, Length, 7 )
	Assert:Equals( 5, PrevSpace )
end )

UnitTest:Test( "FindPreviousSpace - Returns 1 if no space is found", function( Assert )
	local PrevSpace = TextEntryUtil.FindPreviousSpace( Characters, Length, 4 )
	Assert:Equals( 1, PrevSpace )
end )

UnitTest:Test( "FindWordBoundsFromCharacters - Returns expected boundaries", function( Assert )
	local PrevSpace, NextSpace = TextEntryUtil.FindWordBoundsFromCharacters( Characters, Length, 4 )
	Assert:Equals( 1, PrevSpace )
	Assert:Equals( 4, NextSpace )

	PrevSpace, NextSpace = TextEntryUtil.FindWordBoundsFromCharacters( Characters, Length, 5 )
	Assert:Equals( 5, PrevSpace )
	Assert:Equals( 8, NextSpace )

	PrevSpace, NextSpace = TextEntryUtil.FindWordBoundsFromCharacters( Characters, Length, 9 )
	Assert:Equals( 9, PrevSpace )
	Assert:Equals( Length, NextSpace )
end )
