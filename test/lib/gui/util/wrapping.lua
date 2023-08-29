--[[
	Wrapping tests.
]]

local UnitTest = Shine.UnitTest

Shine.GUI = Shine.GUI or {}
Shine.GUI.IsApproximatelyGreaterEqual = Shine.GUI.IsApproximatelyGreaterEqual or function( Left, Right )
	return Left >= Right - 1e-4
end

local Wrapping = require "shine/lib/gui/util/wrapping"

local Label = {
	GetTextWidth = function( self, Text ) return #Text end,
	SetText = function( self, Text ) self.Text = Text end
}

UnitTest:Test( "WordWrap - Wraps a single line of words", function( Assert )
	local RemainingText = Wrapping.WordWrap( Label, "This is a single line of words to be wrapped.", 0, 25 )
	Assert:Nil( RemainingText )
	Assert:Equals( "This is a single line of\nwords to be wrapped.", Label.Text )
end )

UnitTest:Test( "WordWrap - Wraps a line with a single word that is too long", function( Assert )
	local RemainingText = Wrapping.WordWrap(
		Label,
		"This is aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa single line of words to be wrapped.",
		0,
		25
	)
	Assert:Nil( RemainingText )
	Assert:Equals(
		"This is\naaaaaaaaaaaaaaaaaaaaaaaaa\naaaaaaaaaaaaaaa single\nline of words to be\nwrapped.",
		Label.Text
	)
end )

UnitTest:Test( "WordWrap - Stops at line limit with a single word that is too long", function( Assert )
	local RemainingText = Wrapping.WordWrap(
		Label,
		"This is aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa single line of words to be wrapped.",
		0,
		25,
		2
	)
	Assert:Equals(
		"This is\naaaaaaaaaaaaaaaaaaaaaaaaa",
		Label.Text
	)
	Assert:Equals( "aaaaaaaaaaaaaaa single line of words to be wrapped.", RemainingText )
end )

UnitTest:Test( "WordWrap - Handles unsatisfiable wrapping", function( Assert )
	local RemainingText = Wrapping.WordWrap(
		Label,
		"abcdefghi",
		0,
		1
	)
	Assert:Nil( RemainingText )
	Assert:Equals(
		"a\nb\nc\nd\ne\nf\ng\nh\ni",
		Label.Text
	)
end )

UnitTest:Test( "WordWrap - Handles multi-line input", function( Assert )
	local RemainingText = Wrapping.WordWrap(
		Label,
		"This is multiple\nlines of words with\n\nwrapping only required on the last line.",
		0,
		25
	)
	Assert:Nil( RemainingText )
	Assert:Equals(
		"This is multiple\nlines of words with\n\nwrapping only required on\nthe last line.",
		Label.Text
	)
end )

UnitTest:Test( "WordWrap - Handles multi-line input with max lines", function( Assert )
	local RemainingText = Wrapping.WordWrap(
		Label,
		"This is multiple\nlines of words with\nwrapping only required on the last line.",
		0,
		25,
		2
	)
	Assert:Equals(
		"This is multiple\nlines of words with",
		Label.Text
	)
	Assert:Equals( "wrapping only required on the last line.", RemainingText )
end )
