--[[
	Shine unit testing.
]]

Print( "Beginning Shine unit testing..." )

Shine.UnitTest = {}

local UnitTest = Shine.UnitTest
UnitTest.Results = {}

local assert = assert
local DebugTraceback = debug.traceback
local getmetatable = getmetatable
local pairs = pairs
local pcall = pcall
local select = select
local setmetatable = setmetatable
local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
local type = type
local xpcall = xpcall

local IsType = Shine.IsType

function UnitTest:LoadExtension( Name )
	local Plugin = Shine.Plugins[ Name ]

	if not Plugin then
		Shine:LoadExtension( Name )
		Plugin = Shine.Plugins[ Name ]
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
			if type( Value ) == "table" and getmetatable( Value ) == nil then
				local Mock = UnitTest.MockOf( Value )
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
		end
	}
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
	local Lines = StringExplode( Traceback, "\n" )

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

local function DeepEquals( Table1, Table2 )
	if type( Table1 ) ~= type( Table2 ) then return false end
	if type( Table1 ) ~= "table" then return Table1 == Table2 end

	for Key, Value in pairs( Table1 ) do
		local Table2Val = Table2[ Key ]
		if not DeepEquals( Value, Table2Val ) then return false end
	end

	for Key, Value in pairs( Table2 ) do
		local Table1Val = Table1[ Key ]
		if not DeepEquals( Value, Table1Val ) then return false end
	end

	return true
end

UnitTest.Assert = {
	Equals = function( A, B ) return A == B end,
	NotEquals = function( A, B ) return A ~= B end,

	TableEquals = function( A, B )
		for Key, Value in pairs( A ) do
			if Value ~= B[ Key ] then return false end
		end

		for Key, Value in pairs( B ) do
			if Value ~= A[ Key ] then return false end
		end

		return true
	end,

	DeepEquals = DeepEquals,

	ArrayContainsExactly = function( ExpectedValues, Actual )
		if #Actual ~= #ExpectedValues then return false end

		for i = 1, #ExpectedValues do
			local Expected = ExpectedValues[ i ]
			local FoundMatch = false
			for j = 1, #Actual do
				if DeepEquals( Actual[ j ], Expected ) then
					FoundMatch = true
					break
				end
			end

			if not FoundMatch then return false end
		end

		return true
	end,

	True = function( A ) return A == true end,
	Truthy = function( A ) return A end,
	False = function( A ) return A == false end,
	Falsy = function( A ) return not A end,

	Nil = function( A ) return A == nil end,
	NotNil = function( A ) return A ~= nil end,

	Exists = function( Table, Key ) return Table[ Key ] ~= nil end,
	NotExists = function( Table, Key ) return Table[ Key ] == nil end,

	Contains = function( Table, Value )
		for i = 1, #Table do
			if Table[ i ] == Value then return true end
		end

		return false
	end,

	ArrayEquals = table.ArraysEqual,

	IsType = IsType
}

for Name, Func in pairs( UnitTest.Assert ) do
	UnitTest.Assert[ Name ] = function( Description, ... )
		local Success = Func( ... )

		if not Success then
			if IsType( Description, "table" ) then
				Description = "Assertion failed!"
			end

			error( AssertionError{
				Message = Description,
				Args = { ... },
				NumArgs = select( "#", ... )
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
	local Failed = 0
	local Duration = 0

	PrintOutput( "Test results for %s", File )

	for i = 1, #self.Results do
		local Result = self.Results[ i ]

		PrintOutput( "  - %s: %s (%.2fus)", Result.Description, Result.Passed and "PASS" or "FAIL", Result.Duration * 1e6 )

		if Result.Passed then
			Passed = Passed + 1
		else
			Failed = Failed + 1
			PrintOutput( "  Test failure: %s", Result.Description )

			local Err = Result.Err
			if IsAssertionFailure( Err ) then
				for i = 1, Err.NumArgs do
					local AsString = IsType( Err.Args[ i ], "table" ) and table.ToString( Err.Args[ i ] )
						or tostring( Err.Args[ i ] )
					Err.Args[ i ] = StringFormat( "%i. [%s] %s", i, type( Err.Args[ i ] ), AsString )
				end

				Err = StringFormat( "Args:\n%s", TableConcat( Err.Args, "\n------------\n" ) )
			end

			PrintOutput( "Error: %s\n%s", Err, Result.Traceback )
		end

		Duration = Duration + Result.Duration
	end

	PrintOutput( "%d/%d passed, %.2f%% success rate. Time taken: %.2fus.",
		Passed, #self.Results, Passed / #self.Results * 100, Duration * 1e6 )

	return Passed, #self.Results, Duration
end

local Files = {}
Shared.GetMatchingFileNames( "test/*.lua", true, Files )

local FinalResults = {
	Passed = 0, Total = 0, Duration = 0
}
for i = 1, #Files do
	if Files[ i ] ~= "test/test_init.lua" then
		UnitTest:ResetState()

		Script.Load( Files[ i ], true )

		local Passed, Total, Duration = UnitTest:Output( Files[ i ] )
		FinalResults.Passed = FinalResults.Passed + Passed
		FinalResults.Total = FinalResults.Total + Total
		FinalResults.Duration = FinalResults.Duration + Duration

		UnitTest.Results = {}
	end
end

Print( "Total tests run: %i. Pass rate: %.2f%%. Total time: %.2fus.",
	FinalResults.Total, FinalResults.Passed / FinalResults.Total * 100, FinalResults.Duration * 1e6 )
