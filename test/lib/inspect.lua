--[[
	Inspection unit tests.
]]

local function TestFunction() end

local StringEndsWith = string.EndsWith
local StringFormat = string.format
local TableAdd = table.Add
local UnitTest = Shine.UnitTest

local Inspect = require "shine/lib/inspect"

local function RunTests( Tests, Func, Name )
	for i = 1, #Tests do
		local TestCase = Tests[ i ]
		local TestName = StringFormat( "%s should output value for %s as expected", Name, TestCase.Value )
		UnitTest:Test( TestName, function( Assert )
			if TestCase.Expected then
				Assert:Equals( TestCase.Expected, Func( TestCase.Value ) )
			elseif TestCase.ExpectedEndsWith then
				local Output = Func( TestCase.Value )
				Assert.True(
					StringFormat( "Expected %s to end with %s", Output, TestCase.ExpectedEndsWith ),
					StringEndsWith( Output, TestCase.ExpectedEndsWith )
				)
			end
		end )
	end
end

local MockUserdataWithToWatch = newproxy( true )
getmetatable( MockUserdataWithToWatch ).__towatch = function( self ) return "MockUserdataWithToWatch" end

local MockUserdataWithClassName = newproxy( true )
getmetatable( MockUserdataWithClassName ).__index = {
	GetClassName = function( self ) return "Mock" end
}
getmetatable( MockUserdataWithClassName ).__tostring = function( self ) return "MockUserdataWithClassName" end

local UserdataWithoutWatchOrClass = newproxy( true )
getmetatable( UserdataWithoutWatchOrClass ).__tostring = function( self ) return "UserdataWithoutWatchOrClass" end

local BaseTests = {
	{
		Value = 1,
		Expected = "1"
	},
	{
		Value = TestFunction,
		ExpectedEndsWith = "(test/lib/inspect.lua:5)"
	},
	{
		Value = Colour( 1, 1, 1 ),
		Expected = "Colour( 1, 1, 1, 1 )"
	},
	{
		Value = Vector( 1, 1, 1 ),
		Expected = "Vector( 1, 1, 1 )"
	},
	{
		Value = MockUserdataWithToWatch,
		Expected = "MockUserdataWithToWatch"
	},
	{
		Value = MockUserdataWithClassName,
		Expected = "MockUserdataWithClassName (Mock)"
	},
	{
		Value = UserdataWithoutWatchOrClass,
		Expected = "UserdataWithoutWatchOrClass"
	}
}

RunTests( TableAdd( {
	{
		Value = "string\nwith\nnew\nlines",
		Expected = "[==[string\nwith\nnew\nlines]==]"
	},
	{
		Value = "string without newlines",
		Expected = "\"string without newlines\""
	},
}, BaseTests ), Inspect.ToString, "Inspect.ToString" )

RunTests( TableAdd( {
	{
		Value = "string\nwith\nnew\nlines",
		Expected = "[==[string\nwith\nnew\nlines]==]"
	},
	{
		Value = "string without newlines",
		Expected = "\"string without newlines\""
	},
	{
		Value = { 1, 2, 3 },
		ExpectedEndsWith = "(3 array elements, not empty)"
	},
	{
		Value = {},
		ExpectedEndsWith = "(0 array elements, empty)"
	},
	{
		Value = setmetatable( {}, { __tostring = function() return "Test" end, __PrintAsString = true } ),
		Expected = "Test"
	}
}, BaseTests ), Inspect.ToShortString, "Inspect.ToShortString" )

RunTests( TableAdd( {
	{
		Value = "string\nwith\nnew\nlines",
		Expected = "[==[string\nwith\nnew\nlines]==]"
	},
	{
		Value = "string without newlines",
		Expected = "string without newlines"
	},
	{
		Value = { 1, 2, 3 },
		ExpectedEndsWith = "(3 array elements, not empty)"
	},
	{
		Value = {},
		ExpectedEndsWith = "(0 array elements, empty)"
	},
	{
		Value = setmetatable( {}, { __tostring = function() return "Test" end, __PrintAsString = true } ),
		Expected = "Test"
	}
}, BaseTests ), Inspect.ToShortStringKey, "Inspect.ToShortStringKey" )

UnitTest:Test( "SafeToString - Should handle errors in __tostring", function( Assert )
	Assert:Equals(
		"error calling tostring()",
		Inspect.SafeToString( setmetatable( {}, { __tostring = function() error "failed" end } ) )
	)
end )
