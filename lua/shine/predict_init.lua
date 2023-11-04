--[[
	Shine prediction VM startup.
]]

Shine.Hook.CallAfterFileLoad( "lua/DebugUtility.lua", function()
	local OldLog = _G.Log
	if Shine.IsType( OldLog, "function" ) then
		local pcall = pcall
		function Log( FormatString, ... )
			-- Suppress errors in log output to stop prediction VM stutter. The game has some broken log statements
			-- that were never tested.
			pcall( OldLog, FormatString, ... )
		end
	end
end )

-- Load the minimal scripts required to enable extensions, nothing other than game logic is required in this VM.
Shine.LoadScripts( {
	"core/shared/misc.lua",
	"core/shared/logging.lua",
	"core/shared/config.lua",
	"lib/datatables.lua",
	"core/shared/extensions.lua"
} )

-- Sync the log level with the configured level for the client, if possible.
local Data, Err = Shine.LoadJSONFile( "config://shine/cl_config.json" )
if Data then
	local ConfigLogLevel = Data.LogLevel
	if Shine.IsType( ConfigLogLevel, "string" ) then
		local LogLevel = Shine.Objects.Logger.LogLevel[ ConfigLogLevel:upper() ]
		if LogLevel then
			Shine.Logger:SetLevel( LogLevel )
		end
	end
end
