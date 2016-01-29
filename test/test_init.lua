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
local pcall = pcall
local select = select
local setmetatable = setmetatable
local StringExplode = string.Explode
local StringFormat = string.format
local TableConcat = table.concat
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

UnitTest.Assert = {
	Equals = function( A, B ) return A == B end,
	NotEquals = function( A, B ) return A ~= B end,

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

function UnitTest:Output( File )
	local Passed = 0
	local Failed = 0
	local Duration = 0

	for i = 1, #self.Results do
		local Result = self.Results[ i ]

		if Result.Passed then
			Passed = Passed + 1
		else
			Failed = Failed + 1
			Print( "Test failure: %s", Result.Description )

			local Err = Result.Err
			if IsAssertionFailure( Err ) then
				for i = 1, Err.NumArgs do
					local AsString = IsType( Err.Args[ i ], "table" ) and table.ToString( Err.Args[ i ] )
						or tostring( Err.Args[ i ] )
					Err.Args[ i ] = StringFormat( "%i. [%s] %s", i, type( Err.Args[ i ] ), AsString )
				end

				Err = StringFormat( "Args:\n%s", TableConcat( Err.Args, "\n------------\n" ) )
			end

			Print( "Error: %s\n%s", Err, Result.Traceback )
		end

		Duration = Duration + Result.Duration
	end

	Print( "Result summary for %s: %i/%i passed, %.2f%% success rate. Time taken: %.2fus.",
		File, Passed, #self.Results, Passed / #self.Results * 100, Duration * 1e6 )

	return Passed, #self.Results
end

local Files = {}
Shared.GetMatchingFileNames( "test/*.lua", true, Files )

local FinalResults = {
	Passed = 0, Total = 0
}
for i = 1, #Files do
	if Files[ i ] ~= "test/test_init.lua" then
		UnitTest:ResetState()

		Script.Load( Files[ i ], true )

		local Passed, Total = UnitTest:Output( Files[ i ] )
		FinalResults.Passed = FinalResults.Passed + Passed
		FinalResults.Total = FinalResults.Total + Total

		UnitTest.Results = {}
	end
end

Print( "Total tests run: %i. Pass rate: %.2f%%.", FinalResults.Total, FinalResults.Passed / FinalResults.Total * 100 )
