--[[
	Shine black and orange skin.
]]

local Skin = {}

Skin.BrightText = Colour( 1, 1, 1, 1 )
Skin.DarkText = Colour( 1, 1, 1, 1 )

Skin.InactiveButton = Colour( 0.1, 0.1, 0.1, 1 )
Skin.ActiveButton = Colour( 1, 0.6, 0, 1 )
Skin.ButtonBorder = Colour( 0, 0, 0, 1 )

Skin.WindowBackground = Colour( 0.8, 0.8, 0.8, 1 )
Skin.WindowTitle = Colour( 0, 0, 0, 1 )

Skin.TabBackground = Colour( 0.3, 0.3, 0.3, 1 )

Skin.ListHeader = Colour( 0, 0, 0, 1 )
Skin.ActiveListHeader = Colour( 0.3, 0.3, 0.3, 1 )
Skin.ListEntryEven = Colour( 0.1, 0.1, 0.1, 1 )
Skin.ListEntryOdd = Colour( 0.15, 0.15, 0.15, 1 )

Skin.ScrollbarBackground = Colour( 0, 0, 0, 0.2 )
Skin.Scrollbar = Colour( 0.9, 0.5, 0, 1 )

Skin.Tooltip = Colour( 0.1, 0.1, 0.1, 1 )
Skin.TooltipBorder = Colour( 1, 0.6, 0, 1 )

Shine.GUI:RegisterSkin( "Black-Orange", Skin )
