--[[
	Shine client side startup.
]]

local StringFormat = string.format

local Scripts = {
	"lib/locale.lua",
	"lib/timer.lua",
	"core/shared/misc.lua",
	"core/shared/logging.lua",
	"core/shared/config.lua",
	"lib/gui.lua",
	"lib/datatables.lua",
	"lib/query.lua",
	"lib/player.lua",
	"core/shared/commands.lua",
	"core/client/commands.lua",
	"core/client/config.lua",
	"core/shared/votemenu.lua",
	"core/client/votemenu.lua",
	"core/shared/adminmenu.lua",
	"core/client/adminmenu.lua",
	"core/shared/system_notifications.lua",
	"core/shared/extensions.lua",
	"core/shared/chat.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/cl_screentext.lua",
	"core/shared/autocomplete.lua"
}

local StartupMessages = {}
Shine.StartupMessages = StartupMessages

function Shine.AddStartupMessage( Message, Format, ... )
	Message = Format and StringFormat( Message, ... ) or Message

	Message = "- "..Message

	StartupMessages[ #StartupMessages + 1 ] = Message
end

Shine.LoadScripts( Scripts, {
	[ "lib/locale.lua" ] = function()
		Shine.Locale:RegisterSource( "Core", "locale/shine/core" )
	end
} )
Shine.Locale:OnLoaded()
