--[[
	Shine admin startup.
	Loads stuff.
]]

--I have no idea why it's called this.
Shine = {}

local include = Script.Load

--Load order.
local Scripts = {
	"lib/debug.lua",
	"lib/table.lua",
	"lib/string.lua",
	"lib/math.lua",
	"lib/class.lua",
	"core/server/hook.lua",
	"lib/player.lua",
	"lib/timer.lua",
	--"Server.lua",
	"core/server/permissions.lua",
	"core/server/commands.lua",
	"core/server/extensions.lua",
	"core/server/config.lua",
	"core/shared/chat.lua",
	"core/server/logging.lua",
	"core/shared/commands.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/sv_screentext.lua",
	"core/shared/votemenu.lua",
	"core/server/votemenu.lua"
}

for i = 1, #Scripts do
	include( "lua/"..Scripts[ i ] )
end

if Shine.Error then return end

Shine:Print( "Shine started up successfully." )
