--[[
	Shine client side startup.
]]

local include = Script.Load

local Scripts = {
	"Client.lua",
	"core/chat.lua",
	"core/sh_commands.lua",
	"core/sh_webpage.lua"
}

for i = 1, #Scripts do
	include( "lua/"..Scripts[ i ] )
end
