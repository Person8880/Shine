--[[
	String UTF-8 library extension tests.
]]

local UnitTest = Shine.UnitTest
local StringByte = string.byte
local StringChar = string.char
local StringFormat = string.format

UnitTest:Test( "GetUTF8Bytes", function( Assert )
	for i = 0, 0x7F do
		Assert.ArrayEquals(
			StringFormat( "Expected 0x%x for ASCII byte value", i ),
			{ i },
			{ string.GetUTF8Bytes( StringChar( i ) ) }
		)
	end
	Assert:ArrayEquals( { 0xC2, 0xA2 }, { string.GetUTF8Bytes( "¢" ) } )
	Assert:ArrayEquals( { 0xE2, 0x82, 0xAC }, { string.GetUTF8Bytes( "€" ) } )
	Assert:ArrayEquals( { 0xF0, 0x90, 0x8D, 0x88 }, { string.GetUTF8Bytes( "𐍈" ) } )

	local function GetBytesForChar( ... )
		return string.GetUTF8Bytes( StringChar( ... ) )
	end

	-- 1 byte sequence, invalid first byte
	for i = 0x80, 0xC1 do
		Assert.Nil( StringFormat( "Expected invalid byte for 0x%x", i ), GetBytesForChar( i ) )
	end
	for i = 0xF5, 0xFF do
		Assert.Nil( StringFormat( "Expected invalid byte for 0x%x", i ), GetBytesForChar( i ) )
	end

	-- 2 byte sequence, invalid second byte
	Assert:Nil( GetBytesForChar( 0xC2, 0x1 ) )
	Assert:Nil( GetBytesForChar( 0xC2, 0xC0 ) )

	-- 3 byte sequence, invalid second/third bytes
	Assert:Nil( GetBytesForChar( 0xE0, 0xC0, 0x80 ) )
	Assert:Nil( GetBytesForChar( 0xE0, 0x1, 0x80 ) )
	Assert:Nil( GetBytesForChar( 0xE0, 0xA0, 0xC0 ) )
	Assert:Nil( GetBytesForChar( 0xE0, 0xA0, 0x1 ) )

	-- Edge case, byte 1 = 0xE0 (overlong encoding)
	Assert:Nil( GetBytesForChar( 0xE0, 0x80, 0x80 ) )
	Assert:Nil( GetBytesForChar( 0xE0, 0xC0, 0x80 ) )
	-- Edge case, byte 1 = 0xED (UTF-16 surrogate half)
	Assert:Nil( GetBytesForChar( 0xED, 0xA0, 0x80 ) )

	-- 4 byte sequence, invalid second/third/fourth bytes
	Assert:Nil( GetBytesForChar( 0xF0, 0x1, 0x80, 0x80 ) )
	Assert:Nil( GetBytesForChar( 0xF0, 0xC0, 0x80, 0x80 ) )

	Assert:Nil( GetBytesForChar( 0xF0, 0x90, 0x1, 0x80 ) )
	Assert:Nil( GetBytesForChar( 0xF0, 0x90, 0xC0, 0x80 ) )

	Assert:Nil( GetBytesForChar( 0xF0, 0x90, 0x80, 0x1 ) )
	Assert:Nil( GetBytesForChar( 0xF0, 0x90, 0x80, 0xC0 ) )

	-- Edge case, byte 1 = 0xF0 (overlong encoding)
	Assert:Nil( GetBytesForChar( 0xF0, 0x80, 0x80, 0x80 ) )
	-- Edge case, byte 1 = 0xF4 (overlong encoding)
	Assert:Nil( GetBytesForChar( 0xF4, 0x90, 0x80, 0x80 ) )
end )

UnitTest:Test( "UTF8Char", function( Assert )
	Assert:Equals( "$", string.UTF8Char( 0x24 ) )
	Assert:Equals( "¢", string.UTF8Char( 0x00A2 ) )
	Assert:Equals( "€", string.UTF8Char( 0x20AC ) )
	Assert:Equals( "𐍈", string.UTF8Char( 0x10348 ) )
end )

UnitTest:Test( "UTF8Encode", function( Assert )
	local TestChars = { "$", "¢", "€", "𐍈" }
	for i = 1, 4 do
		local Chars, Length = string.UTF8Encode( TestChars[ i ] )
		Assert:ArrayEquals( { TestChars[ i ] }, Chars )
		Assert:Equals( 1, Length )
	end

	local InvalidChar = StringChar( 128, 245 )
	local ReplacementChar = string.UTF8Char( 0xFFFD )

	Assert.ArrayEquals(
		"Should replace both invalid bytes with the replacement character",
		{ ReplacementChar, ReplacementChar },
		string.UTF8Encode( InvalidChar )
	)

	Assert.ArrayEquals(
		"Should replace invalid bytes with the replacement character, but leave valid bytes alone",
		{ ReplacementChar, ReplacementChar, "$", ReplacementChar, "$" },
		string.UTF8Encode( StringChar( 128, 245, 0x24, 128, 0x24 ) )
	)

	local Chars, Length = string.UTF8Encode( "$¢€𐍈" )
	Assert:ArrayEquals( { "$", "¢", "€", "𐍈" }, Chars )
	Assert:Equals( 4, Length )
end )

UnitTest:Test( "UTF8Chars", function( Assert )
	local ReplacementChar = string.UTF8Char( 0xFFFD )
	local Expected = {
		{ 2, ReplacementChar },
		{ 3, ReplacementChar },
		{ 4, "$" },
		{ 5, ReplacementChar },
		{ 6, "$" },
		{ 8, "¢" },
		{ 11, "€" },
		{ 15, "𐍈" }
	}
	local Count = 0
	for ByteIndex, Char in string.UTF8Chars( StringChar( 128, 245, 0x24, 128, 0x24 ).."¢€𐍈" ) do
		Count = Count + 1
		Assert.Equals(
			StringFormat( "Char %d was not at the expected index", Count ),
			Expected[ Count ][ 1 ], ByteIndex
		)
		Assert.Equals(
			StringFormat( "Char %d was not the expected value", Count ),
			Expected[ Count ][ 2 ], Char
		)
	end

	Assert.Equals( "Did not iterate all characters in the given string", #Expected, Count )
end )

local FullUTF8String = "$¢€𐍈"

UnitTest:Test( "UTF8Length", function( Assert )
	Assert:Equals( 4, string.UTF8Length( "$bcd" ) )
	Assert:Equals( 4, string.UTF8Length( "$¢cd" ) )
	Assert:Equals( 4, string.UTF8Length( "$¢€d" ) )
	Assert:Equals( 4, string.UTF8Length( FullUTF8String ) )

	Assert:Equals( 0, string.UTF8Length( "" ) )
end )

UnitTest:Test( "UTF8Sub", function( Assert )
	Assert:Equals( "", string.UTF8Sub( "", 1, 1 ) )
	Assert:Equals( "", string.UTF8Sub( "", 0, 0 ) )
	Assert:Equals( "", string.UTF8Sub( FullUTF8String, 0, 0 ) )
	Assert:Equals( "", string.UTF8Sub( FullUTF8String, 1, 0 ) )

	Assert:Equals( "𐍈", string.UTF8Sub( FullUTF8String, -1 ) )
	Assert:Equals( "€𐍈", string.UTF8Sub( FullUTF8String, -2, -1 ) )
	Assert:Equals( "$¢", string.UTF8Sub( FullUTF8String, 1, 2 ) )
	Assert:Equals( "$¢", string.UTF8Sub( FullUTF8String, 0, 2 ) )
end )

UnitTest:Test( "UTF8Replace", function( Assert )
	Assert:Equals( "ABCD", string.UTF8Replace( FullUTF8String, {
		[ "$" ] = "A",
		[ "¢" ] = "B",
		[ "€" ] = "C",
		[ "𐍈" ] = "D"
	} ) )
end )

UnitTest:Test( "UTF8Reverse", function( Assert )
	Assert:Equals( "𐍈€¢$", string.UTF8Reverse( FullUTF8String ) )
	Assert:Equals( "𐍈€¢$A", string.UTF8Reverse( "A"..FullUTF8String ) )
end )

UnitTest:Test( "UTF8CodePoint", function( Assert )
	Assert:Equals( 0x24, string.UTF8CodePoint( 0x24 ) )
	Assert:Equals( 0xA2, string.UTF8CodePoint( 0xC2, 0xA2 ) )
	Assert:Equals( 0x20AC, string.UTF8CodePoint( 0xE2, 0x82, 0xAC ) )
	Assert:Equals( 0x10348, string.UTF8CodePoint( 0xF0, 0x90, 0x8D, 0x88 ) )
end )

UnitTest:Test( "NormaliseUTF8Whitespace", function( Assert )
	Assert:Equals( string.rep( " ", 29 ).."hi", string.NormaliseUTF8Whitespace( "\t\n\v\f\r  ᠎           ​‌‍    ⁠　﻿hi" ) )
	Assert:Equals( "hi", string.NormaliseUTF8Whitespace( "\t\n\v\f\r  ᠎           ​‌‍    ⁠　﻿hi", "" ) )
end )

UnitTest:Test( "ContainsNonUTF8Whitespace", function( Assert )
	Assert:True( string.ContainsNonUTF8Whitespace( "  ᠎           ​‌‍    ⁠　﻿hi" ) )
	Assert:False( string.ContainsNonUTF8Whitespace( "\t\n\v\f\r  ᠎           ​‌‍    ⁠　﻿" ) )
end )
