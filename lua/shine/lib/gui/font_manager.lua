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

--[[
	Gets the actual height in pixels of the given font in the given family.
]]
function FontManager.GetFontSize( FontFamily, FontName )
	local Fonts = FontFamilies[ FontFamily ]
	if not Fonts then return nil end

	return Fonts[ FontName ]
end

local FontSizes = {
	[ SGUI.Fonts.Ionicons ] = 32
}

--[[
	Gets the actual height in pixels of the given font name.
]]
function FontManager.GetFontSizeForFontName( FontName )
	return FontSizes[ FontName ]
end

Shine.Hook.Add( "OnMapLoad", "CalculateFontSizes", function()
	local Fonts = {}
	Shared.GetMatchingFileNames( "fonts/*.fnt", false, Fonts )

	-- Collect known font sizes upfront.
	for i = 1, #_G.FontFamilies do
		local FontFamily = _G.FontFamilies[ _G.FontFamilies[ i ] ]
		if Shine.IsType( FontFamily, "table" ) then
			for FontName, Size in pairs( FontFamily ) do
				FontSizes[ FontName ] = Size
			end
		end
	end

	local StringChar = string.char
	local Chars = { "!", "(", ")", "[", "]" }
	-- 0 -> 9
	for i = 48, 57 do
		Chars[ #Chars + 1 ] = StringChar( i )
	end
	-- A -> Z (we assume lower case will always be shorter)
	for i = 65, 90 do
		Chars[ #Chars + 1 ] = StringChar( i )
	end

	local CalculateTextSize = GUI.CalculateTextSize
	local GetCanFontRenderString = GUI.GetCanFontRenderString
	local IOOpen = io.open
	local Max = math.max
	local StringMatch = string.match

	Shine.Stream( Fonts )
		:Filter( function( Font ) return not FontSizes[ Font ] end )
		:ForEach( function( Font )
			-- First try to use the engine functions to work it out.
			local MaxHeight = 0
			for j = 1, #Chars do
				local Char = Chars[ j ]
				if GetCanFontRenderString( Font, Char ) then
					local Size = CalculateTextSize( Font, Char )
					MaxHeight = Max( MaxHeight, Size.y )

					if MaxHeight > 0 then
						-- Height seems to be returned as the same value for all characters, so stop on the first
						-- supported character.
						FontSizes[ Font ] = MaxHeight
						return
					end
				end
			end

			-- Font doesn't use any expected characters, try to determine it from the file itself.
			local File, Err = IOOpen( Font, "r" )
			if not File then return end

			for Line in File:lines() do
				local LineHeight = StringMatch( Line, "lineHeight=(%d+)" )
				if LineHeight then
					FontSizes[ Font ] = tonumber( LineHeight )
					break
				end
			end

			File:close()
		end )
end, Shine.Hook.MAX_PRIORITY )

Shine.GUI.FontManager = FontManager
