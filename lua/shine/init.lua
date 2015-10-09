--[[
	Shine admin server-side startup.
	Loads stuff.
]]

--Load order.
local Scripts = {
	"lib/debug.lua",
	"lib/table.lua",
	"lib/string.lua",
	"lib/utf8.lua",
	"lib/math.lua",
	"lib/class.lua",
	"lib/map.lua",
	"lib/game.lua",
	"core/shared/hook.lua",
	"core/shared/misc.lua",
	"lib/player.lua",
	"lib/timer.lua",
	"lib/datatables.lua",
	"lib/votes.lua",
	"lib/query.lua",
	"core/shared/config.lua",
	"core/shared/logging.lua",
	"core/server/permissions.lua",
	"core/shared/commands.lua",
	"core/server/commands.lua",
	"core/shared/extensions.lua",
	"core/server/config.lua",
	"core/shared/chat.lua",
	"core/server/logging.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/sv_screentext.lua",
	"core/shared/adminmenu.lua",
	"core/shared/votemenu.lua",
	"core/server/votemenu.lua"
}

local OnLoadedFuncs = {
	[ "lib/game.lua" ] = function()
		Shine.IsNS2Combat = Shine.GetGamemode() == "combat"
		Shine.BaseGamemode = Shine.IsNS2Combat and "combat" or "ns2"
	end
}

Shine.LoadScripts( Scripts, OnLoadedFuncs )

if Shine.Error then
	Shared.Message( "Shine failed to start. Check the console for errors." )

	return
end

Shine:Print( "Shine started up successfully." )
