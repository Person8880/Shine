--[[
	Handles font scaling without the hassle.
]]

local Abs = math.abs

local FontManager = {}

--[[
	Gets a font name and scale value based on the given desired size.

	Will automatically deal with GUIScale.
]]
function FontManager.GetFont( FontFamily, DesiredSize )
	local Scale = GUIScale( 1 )
	local RealSize = Scale * DesiredSize

	local Fonts = FontFamilies[ FontFamily ]
	if not Fonts then return end

	local Best
	local BestDiff = math.huge
	for Name, Size in pairs( Fonts ) do
		local Diff = Abs( Size - RealSize )
		if Diff < BestDiff then
			Best = Name
			BestDiff = Diff
		end
	end

	local Scale = RealSize / Fonts[ Best ]

	return Best, Vector2( Scale, Scale )
end

Shine.GUI.FontManager = FontManager
