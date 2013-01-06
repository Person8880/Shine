--[[
	Shine client side startup.

	If you're running combat, then this is called from MedPack.lua for reasons explained in the file.
]]

local include = Script.Load

local Scripts = {
	"Client.lua",
	"lib/string.lua",
	"lib/table.lua",
	"core/chat.lua",
	"core/sh_commands.lua",
	"core/sh_webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/cl_screentext.lua",
	"core/sh_votemenu.lua",
	"core/cl_votemenu.lua"
}

for i = 1, #Scripts do
	include( "lua/"..Scripts[ i ] )
end
