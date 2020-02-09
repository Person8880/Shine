--[[
	Tests for rich text element.
]]

local UnitTest = Shine.UnitTest
local Text = require "shine/lib/gui/richtext/elements/text"

local TextSizeProvider = {
	GetWidth = function( self, Text )
		return #Text
	end,
	SpaceSize = 1,
	TextHeight = 10
}

UnitTest:Test( "GetLines - Should return self when only one line is present", function( Assert )
	local Element = Text( "A single line of text." )
	Assert.ArrayEquals( "Should return the element on its own", { Element }, Element:GetLines() )
end )

UnitTest:Test( "GetLines - Should copy all properties when multiple lines are present", function( Assert )
	local Element = Text( {
		Value = "Multiple lines\nof\r\ntext.",
		DoClick = function() end
	} )

	Assert.DeepEquals( "Should return each line, preserving properties", {
		Text( {
			Value = "Multiple lines",
			DoClick = Element.DoClick
		} ),
		Text( {
			Value = "of",
			DoClick = Element.DoClick
		} ),
		Text( {
			Value = "text.",
			DoClick = Element.DoClick
		} )
	}, Element:GetLines() )
end )

UnitTest:Test( "Split - Should split into words without text wrapping if unnecessary", function( Assert )
	local Element = Text( {
		Value = "Some words that fit",
		DoClick = function() end
	} )

	local Segments = {}
	Element:Split( 1, TextSizeProvider, Segments, 100, 0 )

	Assert.DeepEquals( "Should split text into words when they fit on a line", {
		{
			Width = 4,
			WidthWithoutSpace = 4,
			Value = "Some",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 6,
			WidthWithoutSpace = 5,
			Value = "words",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 5,
			WidthWithoutSpace = 4,
			Value = "that",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 4,
			WidthWithoutSpace = 3,
			Value = "fit",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		}
	}, Segments )
end )

UnitTest:Test( "Split - Should text wrap a long word if it doesn't fit on the line", function( Assert )
	local Element = Text( {
		Value = string.rep( "a", 11 ),
		DoClick = function() end
	} )

	local Segments = {}
	Element:Split( 1, TextSizeProvider, Segments, 10, 0 )

	Assert.DeepEquals( "Should split text into segments", {
		{
			Width = 10,
			WidthWithoutSpace = 10,
			Value = string.rep( "a", 10 ),
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 1,
			WidthWithoutSpace = 1,
			Value = "a",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		}
	}, Segments )
end )

UnitTest:Test( "Split - Should text wrap accounting for the current position", function( Assert )
	local Element = Text( {
		Value = string.rep( "a", 11 ),
		DoClick = function() end
	} )

	local Segments = {}
	Element:Split( 1, TextSizeProvider, Segments, 15, 5 )

	Assert.DeepEquals( "Should split text into segments", {
		{
			Width = 10,
			WidthWithoutSpace = 10,
			Value = string.rep( "a", 10 ),
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 1,
			WidthWithoutSpace = 1,
			Value = "a",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		}
	}, Segments )
end )

UnitTest:Test( "Split - Should text wrap accounting for the current position not including previous words", function( Assert )
	local Element = Text( {
		Value = "Some words "..string.rep( "a", 16 ),
		DoClick = function() end
	} )

	local Segments = {}
	Element:Split( 1, TextSizeProvider, Segments, 15, 0 )

	Assert.DeepEquals( "Should split text into segments", {
		{
			Width = 4,
			WidthWithoutSpace = 4,
			Value = "Some",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 6,
			WidthWithoutSpace = 5,
			Value = "words",
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 15,
			WidthWithoutSpace = 15,
			Value = string.rep( "a", 15 ),
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		},
		{
			Width = 1,
			WidthWithoutSpace = 1,
			Value = string.rep( "a", 1 ),
			Height = 10,
			OriginalElement = 1,
			DoClick = Element.DoClick,
			Setup = Element.Setup
		}
	}, Segments )
end )

UnitTest:Test( "Merge - Should merge segments as expected", function( Assert )
	local Element = Text( {
		Value = "Test value",
		Think = function() end
	} )

	local Merged = Element:Merge( {
		{
			Value = "Test",
			Width = 5,
			WidthWithoutSpace = 4,
			Height = 10
		},
		{
			Value = "value",
			Width = 6,
			WidthWithoutSpace = 5,
			Height = 10
		}
	}, 1, 2 )
	Assert:DeepEquals( {
		Value = "Test value",
		Width = 10,
		Height = 10,
		Think = Element.Think,
		Setup = Element.Setup
	}, Merged )
end )
