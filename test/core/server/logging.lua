--[[
	Logging unit tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "WrapTextByLength - Does nothing if text is shorter than max length", function( Assert )
	local Lines = {}
	Shine.WrapTextByLength( Lines, string.rep( "a", 79 ), 80, true )
	Assert:ArrayEquals( {
		string.rep( "a", 79 )
	}, Lines )
end )

UnitTest:Test( "WrapTextByLength - Wraps text as expected", function( Assert )
	local Lines = {}
	Shine.WrapTextByLength( Lines, string.rep( "a", 81 ), 80, true )
	Assert:ArrayEquals( {
		string.rep( "a", 80 ),
		"a"
	}, Lines )
end )

UnitTest:Test( "WrapTextByLength - Wraps UTF-8 text as expected", function( Assert )
	local Lines = {}
	Shine.WrapTextByLength( Lines, string.rep( "á", 81 ), 80, true )
	Assert:ArrayEquals( {
		string.rep( "á", 40 ),
		string.rep( "á", 40 ),
		"á"
	}, Lines )
end )

UnitTest:Test( "WrapTextByLength - Wraps words as expected", function( Assert )
	local Lines = {}
	Shine.WrapTextByLength( Lines, string.rep( "test ", 33 ).."test", 80 )
	Assert:ArrayEquals( {
		string.rep( "test ", 15 ).."test",
		string.rep( "test ", 15 ).."test",
		"test test"
	}, Lines )
end )

UnitTest:Test( "WrapTextByLength - Wraps UTF-8 words as expected", function( Assert )
	local Lines = {}
	Shine.WrapTextByLength( Lines, string.rep( "éáíó! ", 33 ).."éáíó!", 80 )
	Assert:ArrayEquals( {
		string.rep( "éáíó! ", 7 ).."éáíó!",
		string.rep( "éáíó! ", 7 ).."éáíó!",
		string.rep( "éáíó! ", 7 ).."éáíó!",
		string.rep( "éáíó! ", 7 ).."éáíó!",
		"éáíó! éáíó!"
	}, Lines )
end )

UnitTest:Test( "WrapTextByLength - Handles single long word followed by short words when word wrapping", function( Assert )
	local Lines = {}
	Shine.WrapTextByLength( Lines, string.rep( "a", 170 ).." test test test test test", 80 )
	Assert:ArrayEquals( {
		string.rep( "a", 80 ),
		string.rep( "a", 80 ),
		string.rep( "a", 10 ).." test test test test test"
	}, Lines )
end )

UnitTest:Test( "WrapTextByLength - Handles single long word when word wrapping", function( Assert )
	local Lines = {}
	Shine.WrapTextByLength( Lines, string.rep( "a", 170 ), 80 )
	Assert:ArrayEquals( {
		string.rep( "a", 80 ),
		string.rep( "a", 80 ),
		string.rep( "a", 10 )
	}, Lines )
end )
