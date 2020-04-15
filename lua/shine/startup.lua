--[[
	Shine entry system startup file.
]]

if Predict then return end

local Trace = debug.traceback()

if Trace:find( "Main.lua" ) or Trace:find( "Loading.lua" ) then return end

do
	local loadfile = loadfile
	local pcall = pcall
	local StringFormat = string.format
	local StringGSub = string.gsub

	-- Allow use of require to load mounted Lua files and indicate errors in loading them.
	package.loaders[ #package.loaders + 1 ] = function( Name )
		local FilePath = StringFormat( "lua/%s.lua", ( StringGSub( Name, "%.", "/" ) ) )
		local Success, Func, Err = pcall( loadfile, FilePath )
		if Success then
			if Func then
				return Func
			end

			return StringFormat( "\n\tfailed to load '%s' from mounted filesystem: %s", FilePath, Err )
		end

		return StringFormat( "\n\terror attempting to load file '%s' from mounted filesystem: %s", FilePath, Func )
	end
end

-- I have no idea why it's called this.
Shine = {}

local include = Script.Load

function Shine.LoadScripts( Scripts, OnLoadedFuncs )
	for i = 1, #Scripts do
		include( "lua/shine/"..Scripts[ i ] )

		if OnLoadedFuncs and OnLoadedFuncs[ Scripts[ i ] ] then
			OnLoadedFuncs[ Scripts[ i ] ]()
		end
	end
end

function Shine.LoadScriptsByPath( Path, Recursive, Reload )
	local PathWithWildcard = Path.."/*.lua"

	if Server then
		Server.AddRestrictedFileHashes( PathWithWildcard )
	end

	local Scripts = {}
	Shared.GetMatchingFileNames( PathWithWildcard, Recursive or false, Scripts )

	for i = 1, #Scripts do
		include( Scripts[ i ], Reload )
	end

	return Scripts
end

local InitScript

if Server then
	InitScript = "lua/shine/init.lua"
elseif Client then
	InitScript = "lua/shine/cl_init.lua"
end

-- Load core scripts upfront to allow hooking into network messages and other such
-- elements before any are registered.
Shine.LoadScripts( {
	"lib/string.lua",
	"lib/debug.lua",
	"lib/utf8.lua",
	"lib/table.lua",
	"lib/sorting.lua",
	"lib/math.lua",
	"lib/objects.lua",
	"lib/class.lua",
	"lib/game.lua",
	"core/shared/hook.lua"
} )

-- This function is totally not inspired by Shine's hook system :P
ModLoader.SetupFileHook( "lua/ConfigFileUtility.lua", InitScript, "pre" )
