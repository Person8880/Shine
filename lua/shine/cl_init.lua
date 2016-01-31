--[[
	Shine client side startup.
]]

local include = Script.Load
local StringFormat = string.format

local Scripts = {
	"lib/debug.lua",
	"lib/string.lua",
	"lib/table.lua",
	"lib/sorting.lua",
	"lib/utf8.lua",
	"lib/math.lua",
	"lib/objects.lua",
	"lib/class.lua",
	"lib/game.lua",
	"lib/locale.lua",
	"core/shared/hook.lua",
	"core/shared/misc.lua",
	"core/shared/logging.lua",
	"lib/gui.lua",
	"lib/datatables.lua",
	"lib/timer.lua",
	"lib/query.lua",
	"lib/player.lua",
	"core/shared/commands.lua",
	"core/client/commands.lua",
	"core/shared/config.lua",
	"core/client/config.lua",
	"core/shared/votemenu.lua",
	"core/client/votemenu.lua",
	"core/shared/adminmenu.lua",
	"core/client/adminmenu.lua",
	"core/shared/extensions.lua",
	"core/shared/chat.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/cl_screentext.lua",
	"core/shared/autocomplete.lua"
}

local OnLoadedFuncs = {
	[ "lib/game.lua" ] = function()
		Shine.IsNS2Combat = Shine.GetGamemode() == "combat"
	end
}

local StartupMessages = {}
Shine.StartupMessages = StartupMessages

function Shine.AddStartupMessage( Message, Format, ... )
	Message = Format and StringFormat( Message, ... ) or Message

	Message = "- "..Message

	StartupMessages[ #StartupMessages + 1 ] = Message
end

Shine.LoadScripts( Scripts, OnLoadedFuncs )
Shine.Locale:RegisterSource( "Core", "locale/shine/core" )
