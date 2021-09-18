--[[
	Shine unit testing.
]]

Print( "Beginning Shine unit testing..." )

local Args = { ... }
local OnlyOutputFailingTests = false
local Files = {}

for i = 1, #Args do
	local Arg = Args[ i ]:gsub( "%s", "" )
	if Arg == "--failures-only" then
		OnlyOutputFailingTests = true
	elseif Arg == "--test-file" then
		Files[ #Files + 1 ] = Args[ i + 1 ]
	end
end

Shine.UnitTest = {}

local UnitTest = Shine.UnitTest
UnitTest.Results = {}

local Abs = math.abs
local assert = assert
local DebugTraceback = debug.traceback
local getmetatable = getmetatable
local pairs = pairs
local pcall = pcall
local rawequal = rawequal
local rawget = rawget
local select = select
local setmetatable = setmetatable
local StringExplode = string.Explode
local StringFormat = string.format
local TableArraysEqual = table.ArraysEqual
local TableClear = require "table.clear"
local TableConcat = table.concat
local TableCopy = table.Copy
local TableDeepEquals = table.DeepEquals
local type = type
local xpcall = xpcall

local IsType = Shine.IsType

function UnitTest:LoadExtension( Name )
	local Plugin = Shine.Plugins[ Name ]

	if not Plugin then
		Shine:LoadExtension( Name )
		Plugin = Shine.Plugins[ Name ]
	elseif not Plugin.Enabled then
		Shine:EnableExtension( Name )
	end

	return Plugin
end

--[[
	Creates a table that passes through to the given table, unless a value is written
	to a key to override it.

	This will also mock any table fields, allowing for seemless mock chains.
]]
function UnitTest.MockOf( Table )
	return setmetatable( {}, {
		__index = function( self, Key )
			local Value = Table[ Key ]

			-- Allow for recursive mocking (e.g. Plugin.Config)
			if type( Value ) == "table" then
				local Mock
				if getmetatable( Value ) == nil then
					Mock = UnitTest.MockOf( Value )
				else
					Mock = TableCopy( Value )
				end

				self[ Key ] = Mock

				return Mock
			end

			return Value
		end
	} )
end

function UnitTest.MockPlugin( Plugin )
	local Mock = UnitTest.MockOf( Plugin )
	-- Stop tests from triggering config writes.
	Mock.SaveConfig = function() end
	return Mock
end

function UnitTest.MakeMockClient( SteamID )
	return {
		SteamID = SteamID,
		GetUserId = function() return SteamID end,
		GetControllingPlayer = function()
			return {
				GetName = function() return "Test" end
			}
		end,
		GetIsVirtual = function() return SteamID == 0 end
	}
end

do
	local MockFunction = {}
	MockFunction.__index = MockFunction

	function MockFunction:Reset()
		TableClear( self.Invocations )
	end

	function MockFunction:GetInvocationCount()
		return #self.Invocations
	end

	function MockFunction:SetImplementation( Impl )
		self.Impl = Impl
	end

	function MockFunction:__call( ... )
		self.Invocations[ #self.Invocations + 1 ] = { ArgCount = select( "#", ... ), ... }
		if self.Impl then
			return self.Impl( ... )
		end
	end

	function UnitTest.MockFunction( Impl )
		return setmetatable( {
			Invocations = {},
			Impl = Impl
		}, MockFunction )
	end
end

local MockedGlobals = {}
function UnitTest.MockGlobal( GlobalName, MockValue )
	local OldValue = _G[ GlobalName ]

	_G[ GlobalName ] = MockValue

	if MockedGlobals[ GlobalName ] ~= nil then
		return
	end

	MockedGlobals[ GlobalName ] = OldValue
end

local AssertionError = setmetatable( {}, {
	__call = function( self, Data )
		return setmetatable( Data, self )
	end
} )

local function IsAssertionFailure( Error )
	return getmetatable( Error ) == AssertionError
end

local function CleanTraceback( Traceback )
	local Lines = StringExplode( Traceback, "\n", true )

	for i = 1, #Lines do
		if Lines[ i ]:find( "^%s*test/test_init.lua:%d+: in function 'Test'" ) then
			return TableConcat( Lines, "\n", 1, i - 2 )
		end
	end

	return Traceback
end

function UnitTest:Before( Action )
	self.Befores[ #self.Befores + 1 ] = Action
end

function UnitTest:After( Action )
	self.Afters[ #self.Afters + 1 ] = Action
end

function UnitTest:ResetState()
	self.Befores = {}
	self.Afters = {}

	-- Restore any global values that were mocked in the file.
	for Key, Value in pairs( MockedGlobals ) do
		_G[ Key ] = Value
		MockedGlobals[ Key ] = nil
	end
end

do
	local function CallPrePostAction( Action )
		local Success, Err = xpcall( Action, DebugTraceback )
		if not Success then
			LuaPrint( Err )
		end
	end

	function UnitTest:Test( Description, TestFunction, Finally, Reps )
		local Result = {
			Description = Description
		}

		local function ErrorHandler( Err )
			Result.Err = Err
			local IsAssertion = IsAssertionFailure( Err )
			Result.Traceback = CleanTraceback( DebugTraceback( IsAssertion and Err.Message or Err,
				IsAssertionFailure( Err ) and 4 or 2 ) )
		end

		Reps = Reps or 1

		Shine.Stream( self.Befores ):ForEach( CallPrePostAction )

		local Start = Shared.GetSystemTimeReal()
		for i = 1, Reps do
			local Success, Err = xpcall( TestFunction, ErrorHandler, self.Assert )
			if not Success then
				Result.Errored = true
				break
			end

			if Finally then
				pcall( Finally )
			end
		end
		Result.Duration = Shared.GetSystemTimeReal() - Start

		Shine.Stream( self.Afters ):ForEach( CallPrePostAction )

		if not Result.Errored then
			Result.Passed = true
		end

		self.Results[ #self.Results + 1 ] = Result
	end
end

local function ArrayToString( Array )
	return StringFormat( "{ %s }", Shine.Stream( Array ):Concat( ", " ) )
end

UnitTest.Assert = {
	Equals = function( A, B ) return A == B, StringFormat( "Expected %s to equal %s", B, A ) end,
	NotEquals = function( A, B ) return A ~= B, StringFormat( "Expected %s to not equal %s", B, A ) end,

	Same = function( A, B )
		return rawequal( A, B ), StringFormat( "Expected %s to be raw-equal to %s", B, A )
	end,
	NotSame = function( A, B ) return
		not rawequal( A, B ), StringFormat( "Expected %s to not be raw-equal to %s", B, A )
	end,

	EqualsWithTolerance = function( A, B, Tolerance )
		Tolerance = Tolerance or 1e-5
		return Abs( A - B ) < Tolerance, StringFormat( "Expected %s to equal %s within %s", B, A, Tolerance )
	end,

	TableEquals = function( A, B )
		for Key, Value in pairs( A ) do
			if Value ~= B[ Key ] then
				return false, StringFormat( "Expected %s to equal %s, but %s[ %s ] ~= %s[ %s ]", B, A, A, Key, B, Key )
			end
		end

		for Key, Value in pairs( B ) do
			if Value ~= A[ Key ] then
				return false, StringFormat( "Expected %s to equal %s, but %s[ %s ] ~= %s[ %s ]", B, A, A, Key, B, Key )
			end
		end

		return true
	end,

	DeepEquals = function( A, B )
		return TableDeepEquals( A, B ), StringFormat( "Expected %s to deep equal %s", B, A )
	end,

	ArrayContainsExactly = function( ExpectedValues, Actual )
		if #Actual ~= #ExpectedValues then
			return false, StringFormat( "Expected %s to contain exactly %s",
				ArrayToString( Actual ), ArrayToString( ExpectedValues ) )
		end

		for i = 1, #ExpectedValues do
			local Expected = ExpectedValues[ i ]
			local FoundMatch = false
			for j = 1, #Actual do
				if TableDeepEquals( Actual[ j ], Expected ) then
					FoundMatch = true
					break
				end
			end

			if not FoundMatch then
				return false, StringFormat( "Expected %s to contain exactly %s",
					ArrayToString( Actual ), ArrayToString( ExpectedValues ) )
			end
		end

		return true
	end,

	True = function( A ) return A == true, StringFormat( "Expected %s to be true", A ) end,
	Truthy = function( A ) return A, StringFormat( "Expected %s to be truthy", A ) end,
	False = function( A ) return A == false, StringFormat( "Expected %s to be false", A ) end,
	Falsy = function( A ) return not A, StringFormat( "Expected %s to be falsy", A ) end,

	Nil = function( A ) return A == nil, StringFormat( "Expected %s to be nil", A ) end,
	NotNil = function( A ) return A ~= nil, StringFormat( "Expected %s to not be nil", A ) end,

	Exists = function( Table, Key )
		return Table[ Key ] ~= nil, StringFormat( "Expected %s[ %s ] to not be nil", Table, Key )
	end,
	NotExists = function( Table, Key )
		return Table[ Key ] == nil, StringFormat( "Expected %s[ %s ] to be nil", Table, Key )
	end,

	Contains = function( Table, Value )
		for i = 1, #Table do
			if Table[ i ] == Value then return true end
		end

		return false, StringFormat( "Expected %s to contain %s", Table, Value )
	end,
	Missing = function( Table, Value )
		for i = 1, #Table do
			if Table[ i ] == Value then
				return false, StringFormat( "Expected %s to not contain %s", Table, Value )
			end
		end
		return true
	end,

	ArrayEquals = function( A, B )
		return TableArraysEqual( A, B ), StringFormat( "Expected %s to match array %s",
			ArrayToString( B ), ArrayToString( A ) )
	end,

	IsType = function( Value, Type )
		return IsType( Value, Type ), StringFormat( "Expected %s to have type %s (but was %s)",
			Value, Type, type( Value ) )
	end,

	Called = function( MockFunction, ... )
		local Invocations = MockFunction.Invocations
		local ExpectedInvocation = {
			ArgCount = select( "#", ... ),
			...
		}

		for i = 1, #Invocations do
			if TableDeepEquals( Invocations[ i ], ExpectedInvocation ) then
				return true
			end
		end

		return false, StringFormat(
			"Expected function to have been called with: %s\nActual invocations: %s",
			ArrayToString( { ... } ),
			table.ToString( Invocations )
		)
	end,

	CalledTimes = function( MockFunction, ExpectedTimes )
		local TimesCalled = #MockFunction.Invocations
		return TimesCalled == ExpectedTimes, StringFormat(
			"Expected function to have been called %s time%s (but was called %s time%s)",
			ExpectedTimes,
			ExpectedTimes == 1 and "" or "s",
			TimesCalled,
			TimesCalled == 1 and "" or "s"
		)
	end
}

for Name, Func in pairs( UnitTest.Assert ) do
	UnitTest.Assert[ Name ] = function( Description, ... )
		local Success, ErrorMessage = Func( ... )

		if not Success then
			if IsType( Description, "table" ) then
				Description = "Assertion failed!"
			end

			Description = StringFormat( "%s [%s]", Description, ErrorMessage )

			local Args = {}
			for i = 1, select( "#", ... ) do
				local Arg = select( i, ... )
				local AsString = IsType( Arg, "table" ) and table.ToString( Arg )
					or tostring( Arg )
				Args[ i ] = StringFormat( "%d. [%s] %s", i, type( Arg ), AsString )
			end

			error( AssertionError{
				Message = Description,
				Args = Args
			}, 2 )
		end
	end
end

UnitTest.Assert.Fail = function( Failure )
	error( Failure, 2 )
end

local WriteToConsole = Shared.OldMessage or Shared.Message
local function PrintOutput( Message, ... )
	WriteToConsole( StringFormat( Message, ... ) )
end

function UnitTest:Output( File )
	local Passed = 0
	local Duration = 0

	if OnlyOutputFailingTests then
		local HasFailures = false
		for i = 1, #self.Results do
			local Result = self.Results[ i ]
			if not Result.Passed then
				HasFailures = true
			else
				Passed = Passed + 1
			end
			Duration = Duration + Result.Duration
		end

		if not HasFailures then return Passed, #self.Results, Duration end

		Passed = 0
		Duration = 0
	end

	PrintOutput( "Test results for %s", File )

	for i = 1, #self.Results do
		local Result = self.Results[ i ]

		if not OnlyOutputFailingTests or not Result.Passed then
			PrintOutput( "- %s: %s (%.2fus)", Result.Description, Result.Passed and "PASS" or "FAIL", Result.Duration * 1e6 )
		end

		if Result.Passed then
			Passed = Passed + 1
		else
			local Err = Result.Err
			if IsAssertionFailure( Err ) then
				Err = StringFormat( "Args:\n%s", TableConcat( Err.Args, "\n------------\n" ) )
			end

			PrintOutput( "%s\n%s\n\n", Err, Result.Traceback )
		end

		Duration = Duration + Result.Duration
	end

	PrintOutput( "%d/%d passed, %.2f%% success rate. Time taken: %.2fus.",
		Passed, #self.Results, Passed / #self.Results * 100, Duration * 1e6 )

	return Passed, #self.Results, Duration
end

if #Files == 0 then
	Shared.GetMatchingFileNames( "test/*.lua", true, Files )
end

local FinalResults = {
	Passed = 0, Total = 0, Duration = 0
}
for i = 1, #Files do
	local FilePath = Files[ i ]
	if FilePath ~= "test/test_init.lua" then
		UnitTest:ResetState()

		local File, Err = loadfile( FilePath )
		if not File then
			PrintOutput( "Syntax error in test file %s: %s", FilePath, Err )
		else
			local Success, Err = xpcall( File, function( Err )
				return StringFormat( "%s\n%s", Err, Shine.StackDump( 1 ) )
			end )
			if not Success then
				PrintOutput( "Execution error in test file %s: %s", FilePath, Err )
			end

			-- Some tests may have executed before an error, so output regardless.
			local Passed, Total, Duration = UnitTest:Output( FilePath )
			FinalResults.Passed = FinalResults.Passed + Passed
			FinalResults.Total = FinalResults.Total + Total
			FinalResults.Duration = FinalResults.Duration + Duration

			UnitTest.Results = {}
		end
	end
end

Print( "Total tests run: %d. Pass rate: %.2f%%. Total time: %.2fus.",
	FinalResults.Total, FinalResults.Passed / FinalResults.Total * 100, FinalResults.Duration * 1e6 )
