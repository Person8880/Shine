--[[
	Shine admin server-side startup.
	Loads stuff.
]]

local Scripts = {
	"core/shared/misc.lua",
	"lib/player.lua",
	"lib/timer.lua",
	"lib/datatables.lua",
	"lib/query.lua",
	"core/shared/config.lua",
	"core/shared/logging.lua",
	"core/server/permissions.lua",
	"core/shared/commands.lua",
	"core/server/commands.lua",
	"core/server/logging.lua",
	"core/shared/system_notifications.lua",
	"core/server/config.lua",
	"core/shared/chat.lua",
	"core/server/chat.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/sv_screentext.lua",
	"core/shared/adminmenu.lua",
	"core/shared/votemenu.lua",
	"core/server/votemenu.lua",
	"core/shared/autocomplete.lua"
}

Server.AddRestrictedFileHashes( "lua/shine/lib/gui/*.lua" )

Shine.BaseGamemode = "ns2"
Shine.LoadScripts( Scripts )

Shine:Print( "Shine started up successfully." )
Shine:SaveLog()
