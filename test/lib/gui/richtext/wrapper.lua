--[[
	Tests for rich text wrapping.
]]

local UnitTest = Shine.UnitTest
local Wrapper = require "shine/lib/gui/richtext/wrapper"

local TextSizeProvider = {
	GetWidth = function( self, Text )
		return #Text
	end
}

local TextToWrap = "Someshortword"

UnitTest:Test( "TextWrap - Returns text as-is when shorter than the max width", function( Assert )
	local Parts = Wrapper.TextWrap( TextSizeProvider, TextToWrap, 100, {} )
	Assert.ArrayEquals( "Should have not split the word", {
		TextToWrap
	}, Parts )
end )

UnitTest:Test( "TextWrap - Should split text into the expected number of parts when it exceeds the max width", function( Assert )
	local Parts = Wrapper.TextWrap( TextSizeProvider, TextToWrap, 5, {} )
	Assert.ArrayEquals( "Should have split the word into 3 parts", {
		"Somes", "hortw", "ord"
	}, Parts )
end )

UnitTest:Test( "TextWrap - Should handle the case where text is exactly the max width", function( Assert )
	local Parts = Wrapper.TextWrap( TextSizeProvider, TextToWrap, #TextToWrap, {} )
	Assert.ArrayEquals( "Should have not split the word", {
		TextToWrap
	}, Parts )
end )

UnitTest:Test( "TextWrap - Should handle the case where text is a multiple of the max width", function( Assert )
	local Parts = Wrapper.TextWrap( TextSizeProvider, string.rep( TextToWrap, 2 ), #TextToWrap, {} )
	Assert.ArrayEquals( "Should have split the word evenly into 2 parts", {
		TextToWrap, TextToWrap
	}, Parts )
end )

UnitTest:Test( "TextWrap - Should be able to split down to 1 character", function( Assert )
	local Parts = Wrapper.TextWrap( TextSizeProvider, TextToWrap, 1, {} )
	Assert.ArrayEquals( "Should have split the word into characters", {
		"S", "o", "m", "e", "s", "h", "o", "r", "t", "w", "o", "r", "d"
	}, Parts )
end )

UnitTest:Test( "TextWrap - Should avoid an infinite loop if the max width constraint is too small", function( Assert )
	local Parts = Wrapper.TextWrap( TextSizeProvider, TextToWrap, 0, {} )
	Assert.ArrayEquals( "Should have split the word into characters to avoid an infinite loop", {
		"S", "o", "m", "e", "s", "h", "o", "r", "t", "w", "o", "r", "d"
	}, Parts )
end )

UnitTest:Test( "WordWrapRichTextLines - Wraps a line whose words split evenly", function( Assert )
	local Line = {
		{
			GetWidth = function() return 50, 50 end
		},
		{
			GetWidth = function() return 50, 50 end
		},
		{
			GetWidth = function() return 10, 10 end
		}
	}
	local WrappedLines = Wrapper.WordWrapRichTextLines( {
		Lines = {
			Line
		},
		MaxWidth = 100,
		TextSizeProvider = TextSizeProvider
	} )

	Assert.DeepEquals( "Should have split the elements evenly", {
		{
			Line[ 1 ],
			Line[ 2 ]
		},
		{
			Line[ 3 ]
		}
	}, WrappedLines )
end )

UnitTest:Test( "WordWrapRichTextLines - Should split and consolidate an element that does not fit on a line", function( Assert )
	local Line = {
		{
			GetWidth = function() return 150, 150 end,
			Split = function( self, Index, TextSizeProvider, Segments, MaxWidth, CurrentWidth )
				Segments[ #Segments + 1 ] = {
					Width = 50,
					WidthWithoutSpace = 50,
					Height = 10,
					OriginalElement = Index
				}
				Segments[ #Segments + 1 ] = {
					Width = 50,
					WidthWithoutSpace = 50,
					Height = 10,
					OriginalElement = Index
				}
				Segments[ #Segments + 1 ] = {
					Width = 50,
					WidthWithoutSpace = 40,
					Height = 10,
					OriginalElement = Index
				}
			end,
			Merge = function( self, Segments, StartIndex, EndIndex )
				local Merged = {}
				for i = StartIndex, EndIndex do
					Merged[ #Merged + 1 ] = Segments[ i ]
				end
				return Merged
			end
		},
		{
			GetWidth = function() return 50, 50 end
		},
		{
			GetWidth = function() return 10, 10 end
		}
	}
	local WrappedLines = Wrapper.WordWrapRichTextLines( {
		Lines = {
			Line
		},
		MaxWidth = 100,
		TextSizeProvider = TextSizeProvider
	} )

	Assert.DeepEquals( "Should have split and re-merged the elements as expected", {
		{
			-- First line should be the merged first element.
			{
				{
					Width = 50,
					WidthWithoutSpace = 50,
					Height = 10,
					OriginalElement = 1
				},
				{
					Width = 50,
					WidthWithoutSpace = 50,
					Height = 10,
					OriginalElement = 1
				}
			}
		},
		{
			-- Second line should be the final segment of the first element, then the second and third elements.
			{
				Width = 50,
				-- This is the width that should be used as it's the first element on the line.
				WidthWithoutSpace = 40,
				Height = 10,
				OriginalElement = 1
			},
			Line[ 2 ],
			Line[ 3 ]
		}
	}, WrappedLines )
end )

UnitTest:Test( "WordWrapRichTextLines - Should split if an element doesn't split evenly to fit the max width", function( Assert )
	local Line = {
		{
			GetWidth = function() return 50, 50 end
		},
		{
			GetWidth = function() return 150, 150 end,
			Split = function( self, Index, TextSizeProvider, Segments, MaxWidth, CurrentWidth )
				Segments[ #Segments + 1 ] = {
					Width = 75,
					WidthWithoutSpace = 75,
					Height = 10,
					OriginalElement = Index
				}
				Segments[ #Segments + 1 ] = {
					Width = 75,
					WidthWithoutSpace = 75,
					Height = 10,
					OriginalElement = Index
				}
			end,
			Merge = function( self, Segments, StartIndex, EndIndex )
				local Merged = {}
				for i = StartIndex, EndIndex do
					Merged[ #Merged + 1 ] = Segments[ i ]
				end
				return Merged
			end
		},
		{
			GetWidth = function() return 10, 10 end
		}
	}
	local WrappedLines = Wrapper.WordWrapRichTextLines( {
		Lines = {
			Line
		},
		MaxWidth = 100,
		TextSizeProvider = TextSizeProvider
	} )

	Assert.DeepEquals( "Should have split the elements as expected", {
		{
			-- First line should be the first element.
			Line[ 1 ]
		},
		{
			-- Second line should be the first segment of the second element.
			{
				Width = 75,
				WidthWithoutSpace = 75,
				Height = 10,
				OriginalElement = 2
			}
		},
		{
			-- Third line should be the second segment of the second element and the final element.
			{
				Width = 75,
				WidthWithoutSpace = 75,
				Height = 10,
				OriginalElement = 2
			},
			Line[ 3 ]
		}
	}, WrappedLines )
end )

UnitTest:Test( "WordWrapRichTextLines - Should handle elements larger than the max width", function( Assert )
	local Line = {
		{
			GetWidth = function() return 50, 50 end,
			Split = function( self, Index, TextSizeProvider, Segments, MaxWidth, CurrentWidth )
				self.OriginalElement = Index
				self.Width = 50
				self.WidthWithoutSpace = 50
				Segments[ #Segments + 1 ] = self
			end
		},
		{
			GetWidth = function() return 50, 50 end,
			Split = function( self, Index, TextSizeProvider, Segments, MaxWidth, CurrentWidth )
				self.OriginalElement = Index
				self.Width = 50
				self.WidthWithoutSpace = 50
				Segments[ #Segments + 1 ] = self
			end
		},
		{
			GetWidth = function() return 10, 10 end,
			Split = function( self, Index, TextSizeProvider, Segments, MaxWidth, CurrentWidth )
				self.OriginalElement = Index
				self.Width = 50
				self.WidthWithoutSpace = 50
				Segments[ #Segments + 1 ] = self
			end
		}
	}
	local WrappedLines = Wrapper.WordWrapRichTextLines( {
		Lines = {
			Line
		},
		MaxWidth = 25,
		TextSizeProvider = TextSizeProvider
	} )

	Assert.DeepEquals( "Should have placed one element per line", {
		{
			Line[ 1 ]
		},
		{
			Line[ 2 ]
		},
		{
			Line[ 3 ]
		}
	}, WrappedLines )
end )
