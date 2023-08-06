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
