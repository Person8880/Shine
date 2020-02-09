--[[
	Chat API tests.
]]

local UnitTest = Shine.UnitTest

local ChatAPI = require "shine/core/shared/chat/chat_api"

UnitTest:Test( "ToRichTextMessage - Converts values as expected with no transformer", function( Assert )
	local Converted = ChatAPI.ToRichTextMessage( {
		{},
		"Hello ",
		{ 255, 255, 0 },
		"there!"
	} )

	Assert.DeepEquals( "Message was not converted as expected.", {
		Colour( 1, 1, 1 ), "Hello ", Colour( 1, 1, 0 ), "there!"
	}, Converted )
end )

UnitTest:Test( "ToRichTextMessage - Converts values as expected with transformer", function( Assert )
	local Converted = ChatAPI.ToRichTextMessage( {
		{},
		"Hello",
		{ 255, 255, 0 },
		"there"
	}, function( Text, Context )
		return Text..Context
	end, "!" )

	Assert.DeepEquals( "Message was not converted as expected.", {
		Colour( 1, 1, 1 ), "Hello!", Colour( 1, 1, 0 ), "there!"
	}, Converted )
end )
