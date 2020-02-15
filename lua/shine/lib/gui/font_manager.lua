--[[
	Handles font scaling without the hassle.
]]

local Abs = math.abs
local TableSort = table.sort

local SGUI = Shine.GUI
SGUI.Fonts = {
	Ionicons = PrecacheAsset "fonts/ionicons.fnt",
	Ionicons64 = PrecacheAsset "fonts/ionicons_64.fnt"
}
SGUI.FontFamilies = {
	Ionicons = "Ionicons",
	AgencyFBDistField = "AgencyFBDistField",
	AgencyFBBoldDistField = "AgencyFBBoldDistField",
	MicrogrammaDistField = "MicrogrammaDistField",
	MicrogrammaBoldDistField = "MicrogrammaBoldDistField",
	MicrogrammaDBolExt = "MicrogrammaDBolExt"
}
SGUI.Icons = {
	Ionicons = require "shine/lib/gui/icons"
}

local function MakeIterable( Lookup )
	local Count = 0
	local IterableCopy = {}

	for FontName, Size in pairs( Lookup ) do
		Count = Count + 1
		IterableCopy[ Count ] = FontName
		IterableCopy[ FontName ] = Size
	end

	TableSort( IterableCopy, function( A, B )
		return Lookup[ A ] < Lookup[ B ]
	end )

	IterableCopy[ 0 ] = Count

	return IterableCopy
end

local FontFamilies = setmetatable( {
	Ionicons = {
		[ SGUI.Fonts.Ionicons ] = 32,
		[ SGUI.Fonts.Ionicons64 ] = 64
	},
	AgencyFBDistField = {
		[ "fonts/AgencyFB_distfield.fnt" ] = 70
	},
	AgencyFBBoldDistField = {
		[ "fonts/AgencyFBExtendedBold_distfield.fnt" ] = 70
	},
	MicrogrammaDistField = {
		[ "fonts/MicrogrammaDMedExt_distfield.fnt" ] = 40
	},
	MicrogrammaBoldDistField = {
		[ "fonts/MicrogrammaDBolExt_distfield.fnt" ] = 40
	},
	MicrogrammaDBolExt = {
		[ PrecacheAsset "fonts/MicrogrammaDBolExt_16.fnt" ] = 29,
		[ PrecacheAsset "fonts/MicrogrammaDBolExt_32.fnt" ] = 59,
		[ _G.Fonts.kMicrogrammaDBolExt_Huge ] = 96,
		[ PrecacheAsset "fonts/MicrogrammaDBolExt_64.fnt" ] = 120
	}
}, {
	__index = function( self, Key )
		local Family = _G.FontFamilies[ Key ]
		if Family then
			Family = MakeIterable( Family )

			self[ Key ] = Family

			return Family
		end

		return nil
	end
} )

for Name, FontFamily in pairs( FontFamilies ) do
	FontFamilies[ Name ] = MakeIterable( FontFamily )
end

local FontManager = {}

local function FindFontForSize( FontFamily, AbsoluteSize )
	local Fonts = FontFamilies[ FontFamily ]
	Shine.AssertAtLevel( Fonts, "Unknown font family: %s", 3, FontFamily )

	local Best
	local BestDiff = math.huge
	for i = 1, Fonts[ 0 ] do
		local Name = Fonts[ i ]
		local Size = Fonts[ Name ]

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

do
	local DISTANCE_FIELD_SHADER = "shaders/DistanceFieldFont.surface_shader"
	local NORMAL_SHADER = "shaders/GUIBasic.surface_shader"

	--[[
		Sets up the given GUIItem based on the given font name.

		If the font is known to use a distance field, the appropriate shader and flag are set.
		Otherwise, if the element was using a distance field font the shader and flag are reset.
	]]
	function FontManager.SetupElementForFontName( TextElement, FontName )
		if GetFontFileUsesDistanceField( FontName ) then
			if not TextElement:IsOptionFlagSet( GUIItem.DistanceFieldFont ) then
				TextElement:SetOptionFlag( GUIItem.DistanceFieldFont )
				TextElement:SetShader( DISTANCE_FIELD_SHADER )
			end
		else
			if TextElement:IsOptionFlagSet( GUIItem.DistanceFieldFont ) then
				TextElement:ClearOptionFlag( GUIItem.DistanceFieldFont )
				TextElement:SetShader( NORMAL_SHADER )
			end
		end
	end
end

local FontSizes = {
	[ SGUI.Fonts.Ionicons ] = 32,
	[ SGUI.Fonts.Ionicons64 ] = 64
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
		local Name = _G.FontFamilies[ i ]
		local FontFamily = _G.FontFamilies[ Name ]

		if Shine.IsType( FontFamily, "table" ) then
			for FontName, Size in pairs( FontFamily ) do
				FontSizes[ FontName ] = Size
			end

			-- Eagerly copy the font data for use in font size calculations.
			FontFamilies[ Name ] = MakeIterable( FontFamily )
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

	-- Make sure font sizes are up to date.
	for Name, FontFamily in pairs( FontFamilies ) do
		for i = 1, FontFamily[ 0 ] do
			local FontName = FontFamily[ i ]
			local Size = FontFamily[ FontName ]

			FontFamily[ FontName ] = FontSizes[ FontName ] or Size
		end
	end
end, Shine.Hook.MAX_PRIORITY )

Shine.GUI.FontManager = FontManager
