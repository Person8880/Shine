--[[
	Code generation tests.
]]

local CodeGen = require "shine/lib/codegen"
local UnitTest = Shine.UnitTest

local DebugGetInfo = debug.getinfo

local Template = [[local NumArgs = select( "#", ... )
assert( NumArgs == 2, "Received "..NumArgs.." argument(s)!" )

local InjectedValue1, InjectedValue2 = ...
return function( {FunctionArguments} )
	return math.max( InjectedValue1, InjectedValue2{Arguments} )
end]]

UnitTest:Test( "GenerateFunctionWithArguments - Generates a 0-arguments function as expected", function( Assert )
	local GeneratedFunction = CodeGen.GenerateFunctionWithArguments( Template, 0, nil, 1, 2 )
	local Info = DebugGetInfo( GeneratedFunction )
	Assert.False( "Generated function should not be a vararg", Info.isvararg )
	Assert.Equals( "Generated function should have 0 parameters", 0, Info.nparams )
	Assert.Equals( "Should return the max of the injected values", 2, GeneratedFunction( 3 ) )
end )

UnitTest:Test( "GenerateFunctionWithArguments - Generates a finite-argument function as expected", function( Assert )
	local GeneratedFunction = CodeGen.GenerateFunctionWithArguments( Template, 2, nil, 1, 2 )
	local Info = DebugGetInfo( GeneratedFunction )
	Assert.False( "Generated function should not be a vararg", Info.isvararg )
	Assert.Equals( "Generated function should have 2 parameters", 2, Info.nparams )
	Assert.Equals( "Should return the max of the injected values and arguments", 4, GeneratedFunction( 3, 4 ) )
end )

UnitTest:Test( "GenerateFunctionWithArguments - Generates a vararg if given math.huge", function( Assert )
	local GeneratedFunction = CodeGen.GenerateFunctionWithArguments( Template, math.huge, nil, 1, 2 )
	local Info = DebugGetInfo( GeneratedFunction )
	Assert.True( "Generated function should be a vararg function", Info.isvararg )
	Assert.Equals( "Should return the max of the injected values and arguments", 4, GeneratedFunction( 3, 4 ) )
end )

UnitTest:Test( "MakeFunctionGenerator - Generates a table of functions with arguments", function( Assert )
	local OnFunctionGenerated = UnitTest.MockFunction()
	local Functions = CodeGen.MakeFunctionGenerator( {
		Template = Template,
		ChunkName = "@test/lib/codegen.lua",
		Args = { 1, 2 },
		InitialSize = 2,
		OnFunctionGenerated = OnFunctionGenerated
	} )
	for i = 0, 3 do
		Assert.Equals( "Should return the max of the arguments the function can see", i + 2, Functions[ i ]( 3, 4, 5 ) )
		Assert.Same( "Should cache functions after the first read", Functions[ i ], Functions[ i ] )

		local Info = DebugGetInfo( Functions[ i ] )
		Assert.False( "Should not be a vararg", Info.isvararg )
		Assert.Equals( "Should have the expected number of parameters", i, Info.nparams )
	end

	Assert.DeepEquals( "Should have invoked the OnFunctionGenerated callback as expected", {
		{
			0,
			Functions[ 0 ],
			false,
			ArgCount = 3
		},
		{
			1,
			Functions[ 1 ],
			false,
			ArgCount = 3
		},
		{
			2,
			Functions[ 2 ],
			false,
			ArgCount = 3
		},
		{
			3,
			Functions[ 3 ],
			true,
			ArgCount = 3
		}
	}, OnFunctionGenerated.Invocations )
end )

UnitTest:Test( "MakeFunctionGenerator - Respects the NumArgs parameter", function( Assert )
	local OnFunctionGenerated = UnitTest.MockFunction()
	local Functions = CodeGen.MakeFunctionGenerator( {
		Template = Template,
		ChunkName = "@test/lib/codegen.lua",
		Args = { 1, 2, 3, 4 },
		InitialSize = 3,
		NumArgs = 2
	} )
	for i = 0, 3 do
		Assert.Equals( "Should return the max of the arguments the function can see", i + 2, Functions[ i ]( 3, 4, 5 ) )

		local Info = DebugGetInfo( Functions[ i ] )
		Assert.False( "Should not be a vararg", Info.isvararg )
		Assert.Equals( "Should have the expected number of parameters", i, Info.nparams )
	end
end )
