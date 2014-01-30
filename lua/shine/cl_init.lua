--[[
	Shine client side startup.
]]

Shine = {}

local include = Script.Load
local Notify = Shared.Message
local StringFormat = string.format

local Scripts = {
	"lib/debug.lua",
	"lib/string.lua",
	"lib/utf8.lua",
	"lib/table.lua",
	"lib/class.lua",
	"lib/math.lua",
	"core/shared/hook.lua",
	"core/shared/logging.lua",
	"lib/gui.lua",
	"lib/datatables.lua",
	"lib/timer.lua",
	"lib/query.lua",
	"core/client/commands.lua",
	"core/shared/config.lua",
	"core/shared/votemenu.lua",
	"core/client/votemenu.lua",
	"core/shared/extensions.lua",
	"core/shared/chat.lua",
	"core/shared/commands.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/cl_screentext.lua",
	"core/shared/misc.lua"
}

local StartupMessages = {}
Shine.StartupMessages = StartupMessages

function Shine.AddStartupMessage( Message, Format, ... )
	Message = Format and StringFormat( Message, ... ) or Message

	Message = "- "..Message

	StartupMessages[ #StartupMessages + 1 ] = Message
end

for i = 1, #Scripts do
	include( "lua/shine/"..Scripts[ i ] )
end
