--[[
	Tests for rich text formatting.
]]

local UnitTest = Shine.UnitTest

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local RichTextFormat = require "shine/lib/gui/richtext/format"

UnitTest:Test( "FromInterpolationString - Produces expected output", function( Assert )
	local Message = RichTextFormat.FromInterpolationString( "This is a {Test} {Message:Upper}!", {
		Values = {
			Test = "test",
			Message = "message"
		},
		Colours = {
			Test = Colour( 1, 0, 0 ),
			Message = function( Values )
				return Values.Test == "test" and Colour( 1, 1, 0 ) or Colour( 0, 0, 0 )
			end
		},
		DefaultColour = Colour( 0.5, 0.5, 0.5 )
	} )

	Assert.DeepEquals( "Should have split the message into its colour and text pairs", {
		ColourElement( Colour( 0.5, 0.5, 0.5 ) ),
		TextElement( "This is a " ),
		ColourElement( Colour( 1, 0, 0 ) ),
		TextElement( "test " ),
		ColourElement( Colour( 1, 1, 0 ) ),
		TextElement( "MESSAGE" ),
		ColourElement( Colour( 0.5, 0.5, 0.5 ) ),
		TextElement( "!" )
	}, Message )
end )

UnitTest:Test( "FromInterpolationString - Handles arguments next to each other", function( Assert )
	local Message = RichTextFormat.FromInterpolationString( "{Test}{Message:Upper}", {
		Values = {
			Test = "test",
			Message = "message"
		},
		Colours = {
			Test = Colour( 1, 0, 0 )
		}
	} )

	Assert.DeepEquals( "Should have split the message into its colour and text pairs", {
		ColourElement( Colour( 1, 0, 0 ) ),
		TextElement( "test" ),
		ColourElement( Colour( 1, 1, 1 ) ),
		TextElement( "MESSAGE" )
	}, Message )
end )

UnitTest:Test( "FromInterpolationString - Consolidates elements with the same colour", function( Assert )
	local Message = RichTextFormat.FromInterpolationString( "This is a {Test} {Message}!", {
		Values = {
			Test = "test",
			Message = "message"
		},
		Colours = {
			Test = Colour( 1, 1, 1 ),
			Message = Colour( 1, 0, 0 )
		}
	} )

	Assert.DeepEquals( "Should have split the message into minimal colour and text pairs", {
		ColourElement( Colour( 1, 1, 1 ) ),
		TextElement( "This is a test " ),
		ColourElement( Colour( 1, 0, 0 ) ),
		TextElement( "message" ),
		ColourElement( Colour( 1, 1, 1 ) ),
		TextElement( "!" )
	}, Message )
end )

UnitTest:Test( "FromInterpolationString - Returns entire text if no format arguments are present", function( Assert )
	local Message = RichTextFormat.FromInterpolationString( "This is a test message!", {
		Values = {},
		Colours = {}
	} )

	Assert.DeepEquals( "Should use the default colour for the entire message", {
		ColourElement( Colour( 1, 1, 1 ) ),
		TextElement( "This is a test message!" )
	}, Message )
end )
