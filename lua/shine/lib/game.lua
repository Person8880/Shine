--[[
	Gamemode stuff.
]]

local Gamemode

--[[
	Gets the name of the currently running gamemode.
]]
function Shine.GetGamemode()
	if Gamemode then return Gamemode end

	local GameSetup = io.open( "game_setup.xml", "r" )

	if not GameSetup then
		Gamemode = "ns2"

		return "ns2"
	end

	local Data = GameSetup:read( "*all" )

	GameSetup:close()

	local Match = Data:match( "<name>(.+)</name>" )

	Gamemode = Match or "ns2"

	return Gamemode
end
