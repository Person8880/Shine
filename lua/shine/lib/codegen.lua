--[[
	Code generation helpers.
]]

local Huge = math.huge
local load = load
local select = select
local StringFormat = string.format
local StringGSub = string.gsub
local TableConcat = table.concat
local type = type
local unpack = unpack

local CodeGen = {}

--[[
	Applies template values to the given string.
	Inputs:
		1. The function code to be used as a template. This should be a valid Lua string with placeholders expressed
		   as {Placeholder}. Each placeholder will have the corresponding value in the template values substituted.
		2. The template values to replace placeholders with.
	Output:
		The generated string with all variables substituted.
]]
local function ApplyTemplateValues( FunctionCode, TemplateValues )
	Shine.TypeCheck( FunctionCode, "string", 1, "ApplyTemplateValues" )
	Shine.TypeCheck( TemplateValues, "table", 2, "ApplyTemplateValues" )

	return ( StringGSub( FunctionCode, "{([^%s]+)}", TemplateValues ) )
end
CodeGen.ApplyTemplateValues = ApplyTemplateValues

--[[
	Generates a function from a template, where template values are replaced with the values in the given template
	values table.

	Inputs:
		1. The function code to be used as a template. This should be a valid Lua string with placeholders expressed
		   as {Placeholder}. Each placeholder will have the corresponding value in the template values substituted.
		2. The source to give the loaded function (shown in error tracebacks).
		3. The template values to replace placeholders with.
		... Any values to pass to the chunk (e.g. to provide upvalues).
	Output:
		The generated function.
]]
local function GenerateTemplatedFunction( FunctionCode, ChunkName, TemplateValues, ... )
	Shine.TypeCheck( FunctionCode, "string", 1, "GenerateTemplatedFunction" )
	Shine.TypeCheck( ChunkName, { "string", "nil" }, 2, "GenerateTemplatedFunction" )
	Shine.TypeCheck( TemplateValues, "table", 3, "GenerateTemplatedFunction" )

	local GeneratedFunctionCode = ApplyTemplateValues( FunctionCode, TemplateValues )
	return load( GeneratedFunctionCode, ChunkName )( ... )
end
CodeGen.GenerateTemplatedFunction = GenerateTemplatedFunction

--[[
	Generates a function from a template with the given number of arguments.

	This is useful to use the same function template to handle varying number of arguments without needing a vararg
	which can cause traces to abort.

	This is an expensive operation, and thus should be done upfront or lazily where possible. The intention is to
	spend a bit more time upfront to give the compiler a much easier time later.

	Inputs:
		1. The function code to be used as a template. This should be a valid Lua string with placeholders for:
			* FunctionArguments - the generated arguments for the function, without a ", " at the front.
			* Arguments - the generated arguments, with a ", " at the front to pass in front of known static arguments.
		   It is expected that the given chunk returns a function.
		2. The number of arguments to generate the function with. Can be math.huge to indicate a vararg should be used.
		3. The source to give the loaded function (shown in error tracebacks).
		... Any values to pass to the chunk (e.g. to provide upvalues).
	Output:
		The generated function.
]]
local function GenerateFunctionWithArguments( FunctionCode, NumArguments, ChunkName, ... )
	Shine.TypeCheck( FunctionCode, "string", 1, "GenerateFunctionWithArguments" )
	Shine.TypeCheck( NumArguments, "number", 2, "GenerateFunctionWithArguments" )
	Shine.TypeCheck( ChunkName, { "string", "nil" }, 3, "GenerateFunctionWithArguments" )

	local Arguments = { "" }
	if NumArguments < Huge then
		for i = 1, NumArguments do
			Arguments[ i + 1 ] = StringFormat( "Arg%d", i )
		end
	else
		Arguments[ 2 ] = "..."
	end

	local ArgumentsList = TableConcat( Arguments, ", " )
	local ArgumentsWithoutPrefix = TableConcat( Arguments, ", ", 2 )

	return GenerateTemplatedFunction( FunctionCode, ChunkName, {
		Arguments = ArgumentsList,
		FunctionArguments = ArgumentsWithoutPrefix
	}, ... )
end
CodeGen.GenerateFunctionWithArguments = GenerateFunctionWithArguments

local NO_ARGS = {}

--[[
	Provides a simple means of generating functions from a template that expect a specific number of arguments.

	By using more specialised functions, var-args can be translated into a defined number of arguments which avoids
	an NYI on the VARG bytecode instruction.

	Input: Options table with the following keys:
	{
		-- Arguments to be passed to the function template (for use as upvalues in the returned function).
		Args = { ... },

		-- An optional name to give to each compiled function (used as the source name in error messages).
		-- If omitted, the chunk's generated content is the source.
		ChunkName = "...",

		-- The maximum number of argument variations to generate upfront without lazy loading.
		-- This generates variations for [0, InitialSize] number of arguments.
		-- Ideally this should cover all expected use cases.
		InitialSize = 5,

		-- The number of arguments in the Args table. Can usually be omitted unless an argument in the middle is nil.
		NumArgs = 1,

		-- The Lua code template to be used when generating functions.
		-- This should return a function which will be the generated function. Arguments are available under "...".
		-- There are 2 template variables:
		-- * FunctionArguments - the generated arguments for the function, without a ", " at the front.
		-- * Arguments - the generated arguments, with a ", " at the front to pass in front of known static arguments.
		Template = "return function( {FunctionArguments} ) return pcall( Something{Arguments} ) end",

		-- An optional callback that is called whenever a new function is generated.
		-- This will be called for all of the initial variations, and any later lazily generated versions.
		-- The third argument will be true for lazily generated variations.
		OnFunctionGenerated = function( NumArguments, Function, WasLazilyGenerated ) end
	}
	Output:
		A table that provides a variation of the given template taking n arguments for each number key n.
		If accessing an argument count that has not yet been generated, it is generated automatically.
]]
function CodeGen.MakeFunctionGenerator( Options )
	local Args = Shine.TypeCheckField( Options, "Args", { "table", "nil" }, "Options" ) or NO_ARGS
	local ChunkName = Shine.TypeCheckField( Options, "ChunkName", { "string", "nil" }, "Options" )
	local NumArgs = Shine.TypeCheckField( Options, "NumArgs", { "number", "nil" }, "Options" ) or #Args
	local Template = Shine.TypeCheckField( Options, "Template", "string", "Options" )

	local OnFunctionGenerated = Options.OnFunctionGenerated
	local HasCallback = Shine.IsCallable( OnFunctionGenerated )

	local Functions = setmetatable( {}, {
		__index = function( self, NumArguments )
			if type( NumArguments ) ~= "number" then
				return nil
			end

			local Function = GenerateFunctionWithArguments(
				Template, NumArguments, ChunkName, unpack( Args, 1, NumArgs )
			)

			self[ NumArguments ] = Function

			if HasCallback then
				OnFunctionGenerated( NumArguments, Function, true )
			end

			return Function
		end
	} )
	for i = 0, Options.InitialSize do
		Functions[ i ] = GenerateFunctionWithArguments( Template, i, ChunkName, unpack( Args, 1, NumArgs ) )
		if HasCallback then
			OnFunctionGenerated( i, Functions[ i ], false )
		end
	end

	return Functions
end

return CodeGen
