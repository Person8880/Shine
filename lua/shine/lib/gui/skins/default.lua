--[[
	Default Shine GUI skin.
]]

local WindowBackground = Colour( 0.5, 0.5, 0.5, 1 )
local DarkButton = Colour( 0.2, 0.2, 0.2, 1 )
local ButtonHighlight = Colour( 0.8, 0.5, 0.1, 1 )
local BrightText = Colour( 1, 1, 1, 1 )

local Skin = {
	Button = {
		Default = {
			ActiveCol = ButtonHighlight,
			InactiveCol = DarkButton,
			TextColour = BrightText
		},
		CloseButton = {
			ActiveCol = Colour( 0.7, 0.2, 0.2, 1 ),
			InactiveCol = Colour( 0.5, 0.2, 0.2, 1 )
		},
		MenuButton = {
			InactiveCol = Colour( 0.25, 0.25, 0.25, 1 )
		},
		CategoryPanelButton = {
			Font = Fonts.kAgencyFB_Small,
			ActiveCol = Colour( 1, 0.4, 0.1, 1 ),
			InactiveCol = Colour( 0.3, 0.3, 0.3, 1 )
		},
		SuccessButton = {
			ActiveCol = Colour( 0.1, 0.6, 0.1, 1 )
		},
		DangerButton = {
			ActiveCol = Colour( 1, 0.2, 0.1, 1 )
		}
	},
	CategoryPanel = {
		Default = {
			Colour = WindowBackground
		}
	},
	CheckBox = {
		Default = {
			BackgroundColour = DarkButton,
			CheckedColour = ButtonHighlight,
			TextColour = BrightText,
			Font = Fonts.kAgencyFB_Small
		}
	},
	ColourLabel = {
		Default = {
			Font = Fonts.kAgencyFB_Small
		}
	},
	Label = {
		Default = {
			Colour = BrightText
		},
		Link = {
			Colour = Colour( 1, 0.8, 0 )
		}
	},
	List = {
		Default = {
			Colour = Colour( 0.2, 0.2, 0.2, 1 ),
			HeaderSize = 32,
			LineSize = 32
		}
	},
	ListEntry = {
		Default = {
			InactiveCol = Colour( 0.4, 0.4, 0.4, 1 ),
			ActiveCol = Colour( 1, 0.4, 0.1, 1 ),
			TextColour = BrightText,
			Font = Fonts.kAgencyFB_Small
		},
		DefaultEven = {
			InactiveCol = Colour( 0.3, 0.3, 0.3, 1 )
		}
	},
	ListHeader = {
		Default = {
			ActiveCol = Colour( 0.6, 0.3, 0.2, 1 ),
			InactiveCol = Colour( 0.2, 0.2, 0.2, 1 ),
			TextColour = BrightText,
			Font = Fonts.kAgencyFB_Small
		}
	},
	Menu = {
		Default = {
			Colour = Colour( 0.25, 0.25, 0.25, 1 )
		}
	},
	Panel = {
		Default = {
			Colour = WindowBackground
		},
		TitleBar = {
			Colour = Colour( 0.25, 0.25, 0.25, 1 )
		},
		MenuPanel = {
			Colour = Colour( 0.25, 0.25, 0.25, 1 )
		}
	},
	ProgressBar = {
		Default = {
			BorderColour = Colour( 0, 0, 0, 1 ),
			Colour = Colour( 0.3, 0.3, 0.3, 1 ),
			ProgressColour = Colour( 0.7, 0.7, 0, 1 )
		}
	},
	Scrollbar = {
		Default = {
			BackgroundColour = Colour( 0, 0, 0, 0.2 ),
			InactiveCol = Colour( 0.7, 0.7, 0.7, 1 ),
			ActiveCol = Colour( 1, 0.6, 0, 1 )
		}
	},
	Slider = {
		Default = {
			DarkLineColour = Colour( 0.2, 0.2, 0.2, 1 ),
			HandleColour = Colour( 0.8, 0.6, 0.1, 1 ),
			LineColour = Colour( 1, 1, 1, 1 )
		}
	},
	TabPanel = {
		Default = {
			TabBackgroundColour = DarkButton,
			PanelColour = WindowBackground
		}
	},
	TabPanelButton = {
		Default = {
			Font = Fonts.kAgencyFB_Small,
			ActiveCol = WindowBackground,
			InactiveCol = DarkButton,
			TextColour = BrightText
		}
	},
	TextEntry = {
		Default = {
			FocusColour = Colour( 0.35, 0.35, 0.35, 1 ),
			DarkColour = Colour( 0.4, 0.4, 0.4, 1 ),
			HighlightColour = Colour( 1, 0.4, 0, 0.5 ),
			PlaceholderTextColour = Colour( 0.9, 0.9, 0.9, 1 ),
			BorderColour = Colour( 0.3, 0.3, 0.3, 1 ),
			BorderSize = Vector2( 1, 1 ),
			States = {
				Focus = {
					BorderColour = Colour( 1, 0.3, 0, 1 )
				}
			}
		}
	},
	Tooltip = {
		Default = {
			TextColour = BrightText,
			Colour = DarkButton
		}
	}
}

Shine.GUI.SkinManager:RegisterSkin( "Default", Skin )
