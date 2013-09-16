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
	"lib/utf8.lua",
	"lib/math.lua",
	"lib/class.lua",
	"core/shared/hook.lua",
	"lib/player.lua",
	"lib/timer.lua",
	"lib/datatables.lua",
	"lib/votes.lua",
	"lib/query.lua",
	"core/server/permissions.lua",
	"core/server/commands.lua",
	"core/shared/extensions.lua",
	"core/shared/config.lua",
	"core/server/config.lua",
	"core/shared/chat.lua",
	"core/shared/logging.lua",
	"core/server/logging.lua",
	"core/shared/commands.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/sv_screentext.lua",
	"core/shared/votemenu.lua",
	"core/server/votemenu.lua",
	"core/shared/misc.lua"
}

for i = 1, #Scripts do
	include( "lua/shine/"..Scripts[ i ] )
	
	if Shine.Error then 
		if Shine.Hook then
			Shine.Hook.Disabled = true
		end

		return
	end
end

if Shine.Error then 
	Shared.Message( "Shine failed to start. Check the console for errors." )

	return 
end

Shine:Print( "Shine started up successfully." )
