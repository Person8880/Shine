--[[
	Shine client side startup.
]]

local include = Script.Load

local Scripts = {
	--"Client.lua",
	"lib/string.lua",
	"lib/table.lua",
	"core/shared/chat.lua",
	"core/shared/commands.lua",
	"core/shared/webpage.lua",
	"lib/screentext/sh_screentext.lua",
	"lib/screentext/cl_screentext.lua",
	"core/shared/votemenu.lua",
	"core/client/votemenu.lua"
}

for i = 1, #Scripts do
	include( "lua/"..Scripts[ i ] )
end
