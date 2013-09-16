--[[
	Default Shine GUI skin.
]]

local Skin = {}

Skin.BrightText = Colour( 1, 1, 1, 1 )
Skin.DarkText = Colour( 0, 0, 0, 1 )

Skin.InactiveButton = Colour( 0.2, 0.2, 0.2, 1 )
Skin.ActiveButton = Colour( 0.5, 0.5, 0.5, 1 )
Skin.ButtonBorder = Colour( 0, 0, 0, 1 )

Skin.TextEntryFocus = Colour( 0.7, 0.7, 0, 1 )
Skin.TextEntry = Colour( 0.4, 0.4, 0.4, 1 )

Skin.WindowBackground = Colour( 0.9, 0.9, 0.9, 1 )
Skin.WindowTitle = Colour( 0.1, 0.3, 0.8, 1 )

Skin.TabBackground = Colour( 0.9, 0.9, 0.9, 1 )

--List settings.
Skin.List = {}

--Header.
Skin.List.HeaderColour = Colour( 0.2, 0.2, 0.2, 1 )
Skin.List.ActiveHeaderColour = Colour( 0.5, 0.5, 0.2, 1 )
Skin.List.HeaderSize = 32
Skin.List.HeaderFont = "fonts/AgencyFB_small.fnt"
Skin.List.HeaderTextColour = Colour( 1, 1, 1, 1 )

--Entry.
Skin.List.LineSize = 32
Skin.List.EntryEven = Colour( 1, 1, 1, 1 )
Skin.List.EntryOdd = Colour( 0.95, 0.95, 0.95, 1 )
Skin.List.EntryActive = Colour( 1, 1, 0.1, 1 )
Skin.List.EntryTextColour = Colour( 0, 0, 0, 1 )

Skin.ScrollbarBackground = Colour( 0, 0, 0, 0.2 )
Skin.Scrollbar = Colour( 0.7, 0.7, 0.7, 1 )

Skin.Tooltip = Colour( 1, 1, 1, 1 )
Skin.TooltipBorder = Colour( 0.1, 0.1, 0.1, 1 )

Skin.TreeBackground = Colour( 1, 1, 1, 1 )
Skin.ActiveNode = Colour( 0.2, 0.9, 1, 1 )
Skin.InactiveNode = Colour( 1, 1, 1, 1 )

Skin.ProgressBarEmpty = Colour( 0.3, 0.3, 0.3, 1 )
Skin.ProgressBar = Colour( 0.7, 0.7, 0, 1 )

Skin.SliderHandle = Colour( 0.2, 0.7, 0.9, 1 )
Skin.SliderLines = Colour( 0, 0, 0, 0 )

Shine.GUI:RegisterSkin( "Default", Skin )
