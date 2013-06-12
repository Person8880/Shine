--[[
	Shine client side startup.
]]

Shine = {}

local include = Script.Load

local Scripts = {
	--"Client.lua",
	"lib/string.lua",
	"lib/table.lua",
	"lib/class.lua",
	"core/shared/chat.lua",
	"core/shared/commands.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/cl_screentext.lua",
	"core/shared/votemenu.lua",
	"core/client/votemenu.lua",
	"core/shared/misc.lua"
}

for i = 1, #Scripts do
	include( "lua/"..Scripts[ i ] )
end
