--[[
	JSON helpers unit tests.
]]

local JSON = require "shine/lib/json"

local UnitTest = Shine.UnitTest

local TestJSON = [[{
	// This is a line comment that will be ignored.
	"Array": [
		{
			"String": "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode \ud801\udc37 // /*.\u0000"
		},
		null,
		"This is\n\r\f\b\t\\a \"string\" with áéíóú unicode \ud801\udc37 // /*.\u0000",
		1.5
	],
	/*
		This is a block comment that will also be ignored.
	*/"Boolean": true,
	"Number": 1.5,
	"Object": {
		"1": "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode \ud801\udc37 // /*.\u0000",
		"2": 1.5,
		"Nested": {
			"Array": [ 1, 2, 3 ],
			"ArrayWithFloatIndex": {
				"1": 1,
				"2": 2,
				"2.5": 3
			},
			"ArrayWithLowerIndex": {
				"0": 0,
				"1": 1,
				"2": 2,
				"3": 3
			},
			"More": {}
		}
	},
// This is another line comment immediately followed by a value.
"String": "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode \ud801\udc37 // /*.\u0000"
}]]
local StringToEscape = "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode 𐐷 // /*."..string.char( 0 )
local ExpectedData = {
	Array = {
		{
			String = StringToEscape
		},
		nil,
		StringToEscape,
		1.5
	},
	Boolean = true,
	Number = 1.5,
	Object = {
		Nested = {
			Array = { 1, 2, 3 },
			More = setmetatable( {}, { __jsontype = "object" } ),
			ArrayWithLowerIndex = { [ "0" ] = 0, [ "1" ] = 1, [ "2" ] = 2, [ "3" ] = 3 },
			ArrayWithFloatIndex = { [ "1" ] = 1, [ "2" ] = 2, [ "2.5" ] = 3 }
		},
		[ "1" ] = StringToEscape,
		[ "2" ] = 1.5
	},
	String = StringToEscape
}

local function Decode( JSONString )
	local Decoder = JSON.DecoderFromString( JSONString )

	local Done, Value, Pos, Err
	repeat
		Done, Value, Pos, Err = Decoder()
	until Done

	return Value, Pos, Err
end

local function AssertDecode( Assert, JSONString, ExpectedValue )
	local Value, Pos, Err = Decode( JSONString )
	Assert.Truthy( Err, Value )
	Assert.DeepEquals( "DecoderFromString should decode JSON as expected", ExpectedValue, Value )
end

UnitTest:Test( "DecoderFromString decodes JSON without trailing whitespace", function( Assert )
	AssertDecode( Assert, TestJSON, ExpectedData )
end )

UnitTest:Test( "DecoderFromString decodes JSON with trailing whitespace", function( Assert )
	AssertDecode( Assert, "\r\n\t   "..TestJSON.."\r\n\t   ", ExpectedData )
end )

local ValidTestCases = {
	{
		JSON = "true",
		Expected = true
	},
	{
		JSON = "false",
		Expected = false
	},
	{
		JSON = "null",
		Expected = nil
	},
	{
		JSON = "\"test\"",
		Expected = "test"
	},
	{
		-- One half of a UTF-16 surrogate pair, should be parsed literally.
		JSON = "\"\\ud800\"",
		Expected = "ud800"
	},
	{
		-- Invalid UTF-16 surrogate pair, should be parsed literally too.
		JSON = "\"\\ud800\\u0020\"",
		Expected = "ud800 "
	},
	{
		JSON = "-1.5e-10",
		Expected = -1.5e-10
	},
	{
		JSON = "1.5e+10",
		Expected = 1.5e10
	},
	{
		JSON = "123e10",
		Expected = 123e10
	},
	{
		JSON = "1",
		Expected = 1
	},
	{
		JSON = "1.5",
		Expected = 1.5
	},
	-- Accept trailing commas, even though techinically it's invalid JSON (more trouble than it's worth to detect this).
	{
		JSON = "[true,false,]",
		Expected = { true, false }
	},
	{
		JSON = "{\"test\":false,}",
		Expected = { test = false }
	}
}
for i = 1, #ValidTestCases do
	local TestCase = ValidTestCases[ i ]
	UnitTest:Test( "DecoderFromString decodes "..TestCase.JSON, function( Assert )
		local Value, Pos, Err = Decode( TestCase.JSON )
		Assert.Nil( "Should not have encountered an error", Err )
		Assert.DeepEquals( "Should have decoded "..TestCase.JSON, TestCase.Expected, Value )
	end )
end

local ErrorTestCases = {
	{
		JSON = "nope",
		Description = "an invalid first character"
	},
	{
		JSON = "tru",
		Description = "an incomplete literal"
	},
	{
		JSON = "true2",
		Description = "an invalid literal"
	},
	{
		JSON = "\"nope",
		Description = "an unterminated string"
	},
	{
		JSON = "{\"test\":true\"fail\":true}",
		Description = "a missing comma in an object"
	},
	{
		JSON = "{\"test\":true",
		Description = "an unterminated object"
	},
	{
		JSON = "[{\"test\":true]",
		Description = "a nested unterminated object"
	},
	{
		JSON = "{\"test\":{\"child\":true}\"test2\":false}",
		Description = "a missing comma between a child object and other fields"
	},
	{
		JSON = "{\"test\"true}",
		Description = "an object with a missing : between a key and value"
	},
	{
		JSON = "{true: false}",
		Description = "an object with an invalid key"
	},
	{
		JSON = "[true\"fail\"]",
		Description = "a missing comma in an array"
	},
	{
		JSON = "[\"test\",true",
		Description = "an unterminated array"
	},
	{
		JSON = "{\"test\":[true,false}",
		Description = "a nested unterminated array"
	},
	{
		JSON = "[[\"child\"]\"test\"}",
		Description = "a missing comma between a child array and other values"
	},
	{
		JSON = "-1..",
		Description = "an invalid number"
	},
	{
		JSON = "// Only a comment",
		Description = "a line comment with no end of line"
	},
	{
		JSON = "// A comment that ends but still no data\n",
		Description = "a line comment that ends with no data"
	},
	{
		JSON = "/* Unterminated block comment",
		Description = "an unterminated block comment"
	},
	{
		JSON = "/* Only a block comment */",
		Description = "a block comment with no data"
	}
}
for i = 1, #ErrorTestCases do
	local TestCase = ErrorTestCases[ i ]
	UnitTest:Test( "DecoderFromString returns an error for "..TestCase.Description, function( Assert )
		local Value, Pos, Err = Decode( TestCase.JSON )
		Assert.Truthy( "Should have returned an error", Err )
		Assert.Nil( "Should not have returned a value", Value )
	end )
end
