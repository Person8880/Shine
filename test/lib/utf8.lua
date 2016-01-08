--[[
	String UTF-8 library extension tests.
]]

local UnitTest = Shine.UnitTest
local StringByte = string.byte
local StringChar = string.char

UnitTest:Test( "GetUTF8Bytes", function( Assert )
	Assert:ArrayEquals( { 0x24 }, { string.GetUTF8Bytes( "$" ) } )
	Assert:ArrayEquals( { 0xC2, 0xA2 }, { string.GetUTF8Bytes( "¢" ) } )
	Assert:ArrayEquals( { 0xE2, 0x82, 0xAC }, { string.GetUTF8Bytes( "€" ) } )
	Assert:ArrayEquals( { 0xF0, 0x90, 0x8D, 0x88 }, { string.GetUTF8Bytes( "𐍈" ) } )

	local function GetBytesForChar( ... )
		return string.GetUTF8Bytes( StringChar( ... ) )
	end

	-- 1 byte sequence, invalid first byte
	Assert:Nil( GetBytesForChar( 128 ) )
	Assert:Nil( GetBytesForChar( 245 ) )

	-- 2 byte sequence, invalid second byte
	Assert:Nil( GetBytesForChar( 194, 1 ) )
	Assert:Nil( GetBytesForChar( 194, 200 ) )

	-- 3 byte sequence, invalid second/third bytes
	Assert:Nil( GetBytesForChar( 224, 1, 1 ) )
	Assert:Nil( GetBytesForChar( 224, 200, 1 ) )
	Assert:Nil( GetBytesForChar( 224, 160, 1 ) )
	Assert:Nil( GetBytesForChar( 224, 160, 200 ) )

	-- Edge case 1, byte 1 = 224
	Assert:Nil( GetBytesForChar( 224, 128, 128 ) )
	Assert:Nil( GetBytesForChar( 224, 192, 128 ) )
	-- Edge case 2, byte 1 = 237
	Assert:Nil( GetBytesForChar( 237, 160, 128 ) )

	-- 4 byte sequence, invalid second/third/fourth bytes
	Assert:Nil( GetBytesForChar( 240, 1, 1, 1 ) )
	Assert:Nil( GetBytesForChar( 240, 200, 1, 1 ) )
	Assert:Nil( GetBytesForChar( 240, 144, 1, 1 ) )
	Assert:Nil( GetBytesForChar( 240, 144, 200, 1 ) )
	Assert:Nil( GetBytesForChar( 240, 144, 128, 1 ) )
	Assert:Nil( GetBytesForChar( 240, 144, 128, 200 ) )

	-- Edge case 1, byte 1 = 240
	Assert:Nil( GetBytesForChar( 240, 128, 128, 128 ) )
	-- Edge case 2, byte 1 = 244
	Assert:Nil( GetBytesForChar( 244, 144, 128, 128 ) )
end )

UnitTest:Test( "UTF8Char", function( Assert )
	Assert:Equals( "$", string.UTF8Char( 0x24 ) )
	Assert:Equals( "¢", string.UTF8Char( 0x00A2 ) )
	Assert:Equals( "€", string.UTF8Char( 0x20AC ) )
	Assert:Equals( "𐍈", string.UTF8Char( 0x10348 ) )
end )

UnitTest:Test( "UTF8Encode", function( Assert )
	Assert:Equals( "$", string.UTF8Encode( "$" )[ 1 ] )
	Assert:Equals( "¢", string.UTF8Encode( "¢" )[ 1 ] )
	Assert:Equals( "€", string.UTF8Encode( "€" )[ 1 ] )
	Assert:Equals( "𐍈", string.UTF8Encode( "𐍈" )[ 1 ] )

	local InvalidChar = StringChar( 128, 245 )
	local ReplacementChar = string.UTF8Char( 0xFFFD )
	Assert:ArrayEquals( { ReplacementChar, ReplacementChar }, string.UTF8Encode( InvalidChar ) )
	Assert:ArrayEquals( { ReplacementChar, "$" }, string.UTF8Encode( StringChar( 128, 0x24 ) ) )

	Assert:ArrayEquals( { "$", "¢", "€", "𐍈" }, string.UTF8Encode( "$¢€𐍈" ) )
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
end )

UnitTest:Test( "UTF8CodePoint", function( Assert )
	Assert:Equals( 0x24, string.UTF8CodePoint( 0x24 ) )
	Assert:Equals( 0xA2, string.UTF8CodePoint( 0xC2, 0xA2 ) )
	Assert:Equals( 0x20AC, string.UTF8CodePoint( 0xE2, 0x82, 0xAC ) )
	Assert:Equals( 0x10348, string.UTF8CodePoint( 0xF0, 0x90, 0x8D, 0x88 ) )
end )
