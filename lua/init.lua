--[[
	Shine admin startup.
	Loads stuff.

	If you're running combat, then this is called from MedPack.lua for reasons explained in the file.
]]

--I have no idea why it's called this.
Shine = {}

local include = Script.Load

--Load order.
local Scripts = {
	"lib/table.lua",
	"lib/string.lua",
	"lib/math.lua",
	"lib/class.lua",
	"core/hook.lua",
	"lib/player.lua",
	"lib/timer.lua",
	"Server.lua",
	"core/permissions.lua",
	"core/commands.lua",
	"core/extensions.lua",
	"core/config.lua",
	"core/chat.lua",
	"core/logging.lua",
	"core/sh_commands.lua",
	"core/sh_webpage.lua"
}

for i = 1, #Scripts do
	include( "lua/"..Scripts[ i ] )
end

if Shine.Error then return end

Shine:Print( "Shine started up successfully." )
