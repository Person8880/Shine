--[[
	Tests for rich text entry control.
]]

local ImageElement = require "shine/lib/gui/richtext/elements/image"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local UnitTest = Shine.UnitTest

local CHAR_WIDTH = 16
local IMAGE_WIDTH = CHAR_WIDTH * 1.5

Shine.GUI = Shine.GUI or {}
Shine.GUI.AddProperty = Shine.GUI.AddProperty or function()
	return function() end, function() end
end

GUI = GUI or {}
GUI.CalculateTextSize = function( Font, Text ) return Vector( #Text * CHAR_WIDTH, 0, 0 ) end

local RichTextEntry
Shine.GUI.Register = function( self, Name, Control )
	RichTextEntry = Control
	RichTextEntry.__index = RichTextEntry
end

Script.Load( "lua/shine/lib/gui/objects/richtextentry.lua", true )

local function RichTextOf( Line )
	return {
		GetWrappedLines = function() return { Line } end
	}
end

local function MakeRichTextEntry( RichText, TextParser )
	local Element = setmetatable( {}, RichTextEntry )
	Element.WidthScale = 1
	Element.RichText = RichText
	Element.TextParser = TextParser
	return Element
end

local function MakeImage( Text, CopyText )
	local Element = ImageElement( {} )
	Element.Text = Text
	Element.CopyText = CopyText
	Element.Size = Vector( IMAGE_WIDTH, 0, 0 )
	return Element
end

local function MakeText( Text )
	local Element = TextElement( Text )
	Element.Width = CHAR_WIDTH * #Text
	return Element
end

local Line = {
	MakeText( "This is a test element " ),
	MakeImage( ":e100:", ":test_emoji:" ),
	MakeText( " with an image." )
}

UnitTest:Test( "IsEmpty - Returns true if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )
	Assert:True( TextEntry:IsEmpty() )
end )

UnitTest:Test( "IsEmpty - Returns true if empty content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( {} ) )
	Assert:True( TextEntry:IsEmpty() )
end )

UnitTest:Test( "IsEmpty - Returns true if empty text has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( { MakeText( "" ) } ) )
	Assert:True( TextEntry:IsEmpty() )
end )

UnitTest:Test( "IsEmpty - Returns false if an image element is set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( { Line[ 2 ] } ) )
	Assert:False( TextEntry:IsEmpty() )
end )

UnitTest:Test( "IsEmpty - Returns false if a non-empty text element is set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( { Line[ 1 ] } ) )
	Assert:False( TextEntry:IsEmpty() )
end )

UnitTest:Test( "GetMaxColumn - Returns 0 if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )

	Assert:Equals( 0, TextEntry:GetMaxColumn() )
end )

UnitTest:Test( "GetMaxColumn - Returns the sum of all rich text elements", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )
	Assert:Equals( 23 + 1 + 15, TextEntry:GetMaxColumn() )
end )

UnitTest:Test( "GetElementIndexForColumn - Returns an image element if it exactly aligns with the column", function( Assert )
	local LastElementIndex, NumColumns = RichTextEntry.GetElementIndexForColumn( Line, 24 )
	Assert:Equals( 2, LastElementIndex )
	Assert:Equals( 24, NumColumns )
end )

UnitTest:Test( "GetElementIndexForColumn - Returns a text element if it contains the column", function( Assert )
	local LastElementIndex, NumColumns = RichTextEntry.GetElementIndexForColumn( Line, 25 )
	Assert:Equals( 3, LastElementIndex )
	Assert:Equals( 39, NumColumns )
end )

UnitTest:Test( "FindWordBounds - Returns empty bounds if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )

	local PrevSpace, NextSpace = TextEntry:FindWordBounds( 0 )
	Assert:Equals( 0, PrevSpace )
	Assert:Equals( 0, NextSpace )
end )

UnitTest:Test( "FindWordBounds - Should return bounds around an image if it is at the given column", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )

	local PrevSpace, NextSpace = TextEntry:FindWordBounds( 24 )
	Assert:Equals( 23, PrevSpace )
	Assert:Equals( 24, NextSpace )
end )

UnitTest:Test( "FindWordBounds - Should return bounds in text behind image if it is directly in front of the given column", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )

	local PrevSpace, NextSpace = TextEntry:FindWordBounds( 23 )
	Assert:Equals( 23, PrevSpace )
	Assert:Equals( 23, NextSpace )
end )

UnitTest:Test( "FindWordBounds - Should return bounds in text if the given column is partway within it", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )

	local PrevSpace, NextSpace = TextEntry:FindWordBounds( 4 )
	Assert:Equals( 0, PrevSpace )
	Assert:Equals( 4, NextSpace )
end )

UnitTest:Test( "GetTextWidth - Should return 0 if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )

	Assert:Equals( 0, TextEntry:GetTextWidth() )
end )

UnitTest:Test( "GetTextWidth - Should return the sum of the widths of each element", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )

	Assert:Equals( CHAR_WIDTH * 23 + IMAGE_WIDTH + CHAR_WIDTH * 15, TextEntry:GetTextWidth() )
end )

UnitTest:Test( "GetColumnTextWidth - Should return 0 if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )

	Assert:Equals( 0, TextEntry:GetColumnTextWidth( 10 ) )
end )

UnitTest:Test( "GetColumnTextWidth - Should return the sum of the widths of each element up to the given column", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )

	Assert:Equals( CHAR_WIDTH * 23 + IMAGE_WIDTH + CHAR_WIDTH, TextEntry:GetColumnTextWidth( 23 + 1 + 1 ) )
	Assert:Equals( CHAR_WIDTH * 10, TextEntry:GetColumnTextWidth( 10 ) )
	Assert:Equals( CHAR_WIDTH * 23 + IMAGE_WIDTH + CHAR_WIDTH * 15, TextEntry:GetColumnTextWidth( 39 ) )
end )

UnitTest:Test( "GetSelectionWidth - Should return the width of the values between the given columns", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )

	Assert:Equals( CHAR_WIDTH * 23 + IMAGE_WIDTH, TextEntry:GetSelectionWidth( { 0, 24 } ) )
	Assert:Equals( CHAR_WIDTH * 13 + IMAGE_WIDTH + CHAR_WIDTH * 6, TextEntry:GetSelectionWidth( { 10, 30 } ) )
end )

UnitTest:Test( "GetTextBetween - Returns an empty string if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )
	Assert:Equals( "", TextEntry:GetTextBetween( 0, 24 ) )
end )

UnitTest:Test( "GetTextBetween - Returns all text until the end if no end column is given", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( { MakeText( "ab" ) } ) )
	Assert:Equals( "ab", TextEntry:GetTextBetween( 1 ) )
	Assert:Equals( "b", TextEntry:GetTextBetween( 2 ) )
end )

UnitTest:Test( "GetTextBetween - Returns the textual content between the two bounds", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )

	Assert:Equals( "", TextEntry:GetTextBetween( 11, 10 ) )
	Assert:Equals( "This is a ", TextEntry:GetTextBetween( 0, 10 ) )
	Assert:Equals( "This is a test element :e100:", TextEntry:GetTextBetween( 0, 24 ) )
	Assert:Equals( "This is a test element :test_emoji:", TextEntry:GetTextBetween( 0, 24, "CopyText" ) )
	Assert:Equals( "This is a test element :e100: with an image.", TextEntry:GetTextBetween( 0, 39 ) )
	Assert:Equals( "This is a test element :test_emoji: with an image.", TextEntry:GetTextBetween( 0, 39, "CopyText" ) )
	Assert:Equals( ":e100: with an image.", TextEntry:GetTextBetween( 24, 39 ) )
	Assert:Equals( " with an image.", TextEntry:GetTextBetween( 25, 39 ) )
	Assert:Equals( "with", TextEntry:GetTextBetween( 26, 29 ) )

	TextEntry = MakeRichTextEntry( RichTextOf( {
		MakeImage( ":e100:" ),
		MakeText( " " ),
		MakeImage( ":e100:" ),
		MakeText( " " ),
		MakeImage( ":e100:" )
	} ) )
	Assert:Equals( ":e100:", TextEntry:GetTextBetween( 1, 1 ) )
	Assert:Equals( ":e100: ", TextEntry:GetTextBetween( 1, 2 ) )
	Assert:Equals( ":e100: :e100:", TextEntry:GetTextBetween( 1, 3 ) )
	Assert:Equals( ":e100: :e100: ", TextEntry:GetTextBetween( 1, 4 ) )
	Assert:Equals( ":e100: :e100: :e100:", TextEntry:GetTextBetween( 1, 5 ) )
end )

UnitTest:Test( "GetText - Returns the whole text content", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )
	Assert:Equals( "This is a test element :e100: with an image.", TextEntry:GetText() )
end )

UnitTest:Test( "GetSelectedText - Returns the text between the selection bounds for copying", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )
	TextEntry.SelectionBounds = { 0, 24 }
	Assert:Equals( "This is a test element :test_emoji:", TextEntry:GetSelectedText() )
end )

UnitTest:Test( "GetColumnForVisualPosition - Returns 0 if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )
	Assert:Equals( 0, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 10 ) )
end )

UnitTest:Test( "GetColumnForVisualPosition - Returns the appropriate column for the given x-offset", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )
	Assert:Equals( 10, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 10 ) )
	Assert:Equals( 10, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 10.5 ) )
	Assert:Equals( 11, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 10.6 ) )
	Assert:Equals( 23, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 23 + IMAGE_WIDTH * 0.25 ) )
	Assert:Equals( 24, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 23 + IMAGE_WIDTH * 0.5 ) )
	Assert:Equals( 24, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 23 + IMAGE_WIDTH ) )
	Assert:Equals( 24, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 23 + IMAGE_WIDTH + CHAR_WIDTH * 0.5 ) )
	Assert:Equals( 25, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 23 + IMAGE_WIDTH + CHAR_WIDTH * 0.6 ) )
	Assert:Equals( 25, TextEntry:GetColumnForVisualPosition( CHAR_WIDTH * 23 + IMAGE_WIDTH + CHAR_WIDTH ) )
end )

UnitTest:Test( "GetColumnFromMouse - Returns the appropriate column for the given x-offset, accounting for text offset", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )
	TextEntry.TextOffset = CHAR_WIDTH * -10
	Assert:Equals( 20, TextEntry:GetColumnFromMouse( CHAR_WIDTH * 10 ) )
end )

UnitTest:Test( "GetVisualColumnFromTextColumn - Returns 0 if no content has been set", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( nil ) )
	Assert:Equals( 0, TextEntry:GetVisualColumnFromTextColumn( 10 ) )
end )

UnitTest:Test( "GetVisualColumnFromTextColumn - Returns the first visual column after the text column", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )
	Assert:Equals( 10, TextEntry:GetVisualColumnFromTextColumn( 10 ) )
	Assert:Equals( 24, TextEntry:GetVisualColumnFromTextColumn( #( "This is a test element :e100:" ) ) )
	Assert:Equals( 25, TextEntry:GetVisualColumnFromTextColumn( #( "This is a test element :e100: " ) ) )
	Assert:Equals( 39, TextEntry:GetVisualColumnFromTextColumn( #( "This is a test element :e100: with an image." ) ) )
end )

UnitTest:Test( "ConvertStateToAutoComplete - Converts the caret position from visual to text space", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ) )
	local State = {
		Text = "This is a test element :e100: with an image.",
		CaretPos = 25
	}

	Assert:DeepEquals( {
		Text = State.Text,
		CaretPos = #( "This is a test element :e100: " )
	}, TextEntry:ConvertStateToAutoComplete( State ) )
end )

UnitTest:Test( "ConvertStateFromAutoComplete - Converts the caret position from visual to text space", function( Assert )
	local TextEntry = MakeRichTextEntry( RichTextOf( Line ), function() return Line end )
	local State = {
		-- This text will be normalised to replace "test_emoji" with "e100", so the caret should shift back accordingly.
		Text = "This is a test element :test_emoji: with an image.",
		CaretPos = 36
	}

	Assert:DeepEquals( {
		Text = State.Text,
		CaretPos = 25
	}, TextEntry:ConvertStateFromAutoComplete( State ) )
end )
