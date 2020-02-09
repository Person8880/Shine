--[[
	Tests for the default chat provider.
]]

local UnitTest = Shine.UnitTest

local DefaultProvider = require "shine/core/shared/chat/default_provider"

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local Conversions = {
	{
		Input = {
			Colour( 1, 0, 0 ),
			"This is a single colour message."
		},
		Output = {
			Colour( 1, 0, 0 ),
			"This is a single colour message."
		}
	},
	{
		Input = {
			Colour( 1, 0, 0 ),
			"This is a single colour message.",
			" It has multiple text values."
		},
		Output = {
			Colour( 1, 0, 0 ),
			"This is a single colour message. It has multiple text values."
		}
	},
	{
		Input = {
			Colour( 1, 0, 0 ),
			"[Some Prefix]",
			Colour( 1, 1, 1 ),
			"Some message."
		},
		Output = {
			Colour( 1, 0, 0 ),
			"[Some Prefix]",
			Colour( 1, 1, 1 ),
			"Some message."
		}
	},
	{
		Input = {
			Colour( 1, 0, 0 ),
			"[Some Prefix]",
			Colour( 1, 1, 1 ),
			"Some message ",
			Colour( 1, 1, 0 ),
			"with more than 2 colours ",
			Colour( 1, 1, 1 ),
			"should ignore colours after the first 2."
		},
		Output = {
			Colour( 1, 0, 0 ),
			"[Some Prefix]",
			Colour( 1, 1, 1 ),
			"Some message with more than 2 colours should ignore colours after the first 2.",
		}
	},
	{
		Input = {
			ColourElement( Colour( 1, 0, 0 ) ),
			TextElement( "[Some Prefix]" ),
			ColourElement( Colour( 1, 1, 1 ) ),
			TextElement( "Some message." )
		},
		Output = {
			Colour( 1, 0, 0 ),
			"[Some Prefix]",
			Colour( 1, 1, 1 ),
			"Some message."
		}
	},
	{
		Input = {
			-- Unrecognised input values should be ignored.
			{}
		}
	}
}

for i = 1, #Conversions do
	UnitTest:Test( "ConvertRichTextToDualColour - Test case "..i, function( Assert )
		local Converted = DefaultProvider.ConvertRichTextToDualColour( Conversions[ i ].Input )
		Assert:DeepEquals( Conversions[ i ].Output, Converted )
	end )
end
