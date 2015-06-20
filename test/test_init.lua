--[[
	Shine unit testing.
]]

Print( "Beginning Shine unit testing..." )

Shine.UnitTest = {}

local UnitTest = Shine.UnitTest
UnitTest.Results = {}

local assert = assert
local DebugGetInfo = debug.getinfo
local DebugTraceback = debug.traceback
local pcall = pcall
local xpcall = xpcall

function UnitTest:Test( Description, TestFunction, Finally )
	local Result = {
		Description = Description,
		FuncInfo = DebugGetInfo( TestFunction, "nS" )
	}

	local function ErrorHandler( Err )
		Result.Err = Err
		Result.Traceback = DebugTraceback()
	end

	local Success, Err = xpcall( TestFunction, ErrorHandler, self.Assert )
	if not Success then
		Result.Errored = true
	else
		Result.Passed = true
	end

	if Finally then
		pcall( Finally )
	end

	self.Results[ #self.Results + 1 ] = Result
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
	NotExists = function( Table, Key ) return Table[ Key ] == nil end
}

for Name, Func in pairs( UnitTest.Assert ) do
	UnitTest.Assert[ Name ] = function( Description, ... )
		local Success = Func( ... )

		if not Success then
			error( { Message = Description, Args = { ... } } )
		end
	end
end

function UnitTest:Output( File )
	local Passed = 0
	local Failed = 0

	for i = 1, #self.Results do
		local Result = self.Results[ i ]

		if Result.Passed then
			Passed = Passed + 1
		else
			Failed = Failed + 1
			Print( "Test failure: %s", Result.Description )
			PrintTable( Result )
		end
	end

	Print( "Result summary for %s: %i/%i passed, %.2f%% success rate.",
		File, Passed, #self.Results, Passed / #self.Results * 100 )

	return Passed, #self.Results
end

local Files = {}
Shared.GetMatchingFileNames( "test/*.lua", true, Files )

local FinalResults = {
	Passed = 0, Total = 0
}
for i = 1, #Files do
	if Files[ i ] ~= "test/test_init.lua" then
		Script.Load( Files[ i ], true )

		local Passed, Total = UnitTest:Output( Files[ i ] )
		FinalResults.Passed = FinalResults.Passed + Passed
		FinalResults.Total = FinalResults.Total + Total

		UnitTest.Results = {}
	end
end

Print( "Total tests run: %i. Pass rate: %.2f%%.", FinalResults.Total, FinalResults.Passed / FinalResults.Total * 100 )
