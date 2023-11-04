--[[
	Content rendering GUIView, used as part of pipeline rendering.
]]

Script.Load( "lua/shine/lib/gui/views/serialise.lua" )

local ItemSerialiser = _G.SGUIItemSerialiser
local Objects

function Update( DeltaTime )
	if _G.NeedsUpdate then
		_G.NeedsUpdate = false
		Objects = ItemSerialiser.DeserialiseObjects( _G )
	end
end
