--[[
	Shine prediction VM startup.
]]

local include = Script.Load
local StringFormat = string.format

-- Load the minimal scripts required to enable extensions, nothing other than game logic is required in this VM.
local Scripts = {
	"core/shared/misc.lua",
	"core/shared/logging.lua",
	"core/shared/config.lua",
	"lib/datatables.lua",
	"core/shared/extensions.lua"
}

Shine.LoadScripts( Scripts )
