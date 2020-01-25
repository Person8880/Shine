--[[
	Handles font scaling without the hassle.
]]

local Abs = math.abs

local SGUI = Shine.GUI
SGUI.Fonts = {
	Ionicons = PrecacheAsset "fonts/ionicons.fnt"
}
SGUI.FontFamilies = {
	Ionicons = "Ionicons"
}
SGUI.Icons = {
	Ionicons = require "shine/lib/gui/icons"
}

local FontFamilies = setmetatable( {
	Ionicons = {
		[ SGUI.Fonts.Ionicons ] = 32
	}
}, {
	__index = function( self, Key )
		return _G.FontFamilies[ Key ]
	end
} )

local FontManager = {}

local function FindFontForSize( FontFamily, AbsoluteSize )
	local Fonts = FontFamilies[ FontFamily ]
	if not Fonts then return end

	local Best
	local BestDiff = math.huge
	for Name, Size in pairs( Fonts ) do
		local Diff = Abs( Size - AbsoluteSize )
		if Diff < BestDiff then
			Best = Name
			BestDiff = Diff
		end
	end

	local Scale = AbsoluteSize / Fonts[ Best ]

	return Best, Vector2( Scale, Scale )
end

--[[
	Gets a font name and scale value based on the given desired size.

	Will automatically deal with GUIScale by scaling the desired size, then
	finding the font that best matches the scaled size.
]]
function FontManager.GetFont( FontFamily, DesiredSize )
	local Scale = SGUI.LinearScale( 1 )
	local AbsoluteSize = Scale * DesiredSize
	return FindFontForSize( FontFamily, AbsoluteSize )
end

--[[
	Gets a font name and scale value based on the given desired size.

	Will automatically scale up the size if the screen height is larger than 1080.
]]
function FontManager.GetHighResFont( FontFamily, DesiredSize )
	local Scale
	local W, H = SGUI.GetScreenSize()
	if H > 1080 then
		Scale = SGUI.LinearScale( 1 )
	else
		Scale = 1
	end

	return FindFontForSize( FontFamily, DesiredSize * Scale )
end

--[[
	Gets a font name and scale based on the given absolute size.

	Will find the font closest to the absolute size provided, ignoring
	GUIScale.
]]
FontManager.GetFontForAbsoluteSize = FindFontForSize

Shine.GUI.FontManager = FontManager
