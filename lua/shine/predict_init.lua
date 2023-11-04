--[[
	Shine prediction VM startup.
]]

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
