--[[
	Default Shine GUI skin.
]]

local Skin = {}

Skin.BrightText = Colour( 1, 1, 1, 1 )
Skin.DarkText = Colour( 0, 0, 0, 1 )

Skin.InactiveButton = Colour( 0.2, 0.2, 0.2, 1 )
Skin.ActiveButton = Colour( 0.5, 0.5, 0.5, 1 )
Skin.ButtonBorder = Colour( 0, 0, 0, 1 )

Skin.MenuButton = Colour( 0.25, 0.25, 0.25, 1 )

Skin.CloseButtonActive = Colour( 0.7, 0.2, 0.2, 1 )
Skin.CloseButtonInactive = Colour( 0.5, 0.2, 0.2, 1 )

Skin.TextEntryFocus = Colour( 1, 0.4, 0.1, 1 )
Skin.TextEntry = Colour( 0.4, 0.4, 0.4, 1 )

Skin.WindowBackground = Colour( 0.5, 0.5, 0.5, 1 )
Skin.WindowTitle = Colour( 0.25, 0.25, 0.25, 1 )

Skin.TabBackground = Colour( 0.9, 0.9, 0.9, 1 )

--List settings.
Skin.List = {}

--Header.
Skin.List.HeaderColour = Colour( 0.2, 0.2, 0.2, 1 )
Skin.List.ActiveHeaderColour = Colour( 0.6, 0.3, 0.2, 1 )
Skin.List.HeaderSize = 32
Skin.List.HeaderFont = Fonts.AgencyFB_Small
Skin.List.HeaderTextColour = Colour( 1, 1, 1, 1 )

--Entry.
Skin.List.LineSize = 32
Skin.List.EntryEven = Colour( 0.3, 0.3, 0.3, 1 )
Skin.List.EntryOdd = Colour( 0.4, 0.4, 0.4, 1 )
Skin.List.EntryActive = Colour( 1, 0.4, 0.1, 1 )
Skin.List.EntryTextColour = Colour( 1, 1, 1, 1 )
Skin.List.EntryFont = Fonts.AgencyFB_Small

Skin.ScrollbarBackground = Colour( 0, 0, 0, 0.2 )
Skin.Scrollbar = Colour( 0.7, 0.7, 0.7, 1 )
Skin.ScrollbarActive = Colour( 1, 0.6, 0, 1 )

Skin.Tooltip = Colour( 1, 1, 1, 1 )
Skin.TooltipBorder = Colour( 0.1, 0.1, 0.1, 1 )

Skin.TreeBackground = Colour( 1, 1, 1, 1 )
Skin.ActiveNode = Colour( 0.2, 0.9, 1, 1 )
Skin.InactiveNode = Colour( 1, 1, 1, 1 )

Skin.ProgressBarEmpty = Colour( 0.3, 0.3, 0.3, 1 )
Skin.ProgressBar = Colour( 0.7, 0.7, 0, 1 )

Skin.SliderHandle = Colour( 0.8, 0.6, 0.1, 1 )
Skin.SliderFillLine = Colour( 1, 1, 1, 1 )
Skin.SliderUnfilledLine = Colour( 0.2, 0.2, 0.2, 1 )

Skin.TabPanel = {}
Skin.TabPanel.TabFont = Fonts.AgencyFB_Small

Skin.CategoryPanel = {}
Skin.CategoryPanel.Font = Fonts.AgencyFB_Small
Skin.CategoryPanel.ActiveCol = Colour( 1, 0.4, 0.1, 1 )
Skin.CategoryPanel.InactiveCol = Colour( 0.3, 0.3, 0.3, 1 )

Shine.GUI:RegisterSkin( "Default", Skin )
