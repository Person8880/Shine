--[[
	Default Shine GUI skin.
]]

local SGUI = Shine.GUI

local WindowBackground = Colour( 0.5, 0.5, 0.5, 1 )
local HorizontalTabBackground = Colour( 0.4, 0.4, 0.4, 1 )
local DarkButton = Colour( 0.2, 0.2, 0.2, 1 )
local ButtonHighlight = Colour( 0.8, 0.5, 0.1, 1 )
local BrightText = Colour( 1, 1, 1, 1 )
local Clear = Colour( 0, 0, 0, 0 )

local Danger = Colour( 1, 0, 0 )
local Warning = Colour( 1, 0.6, 0 )
local Info = Colour( 0, 0.5, 1 )

local SuccessButton = Colour( 0.1, 0.6, 0.1, 1 )
local DangerButton = Colour( 1, 0.2, 0.1, 1 )


local Skin = {
	Button = {
		Default = {
			ActiveCol = ButtonHighlight,
			InactiveCol = DarkButton,
			TextColour = BrightText,
			HighlightOnMouseOver = true,
			States = {
				Disabled = {
					HighlightOnMouseOver = false,
					InactiveCol = SGUI.ColourWithAlpha( DarkButton, 0.5 )
				}
			}
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
			ActiveCol = SuccessButton
		},
		DangerButton = {
			ActiveCol = DangerButton
		},
		AcceptButton = {
			InactiveCol = SuccessButton,
			ActiveCol = SGUI.ColourWithAlpha( SuccessButton, 2 ),
			InheritsParentAlpha = true
		},
		DeclineButton = {
			InactiveCol = DangerButton,
			ActiveCol = SGUI.ColourWithAlpha( DangerButton, 2 ),
			InheritsParentAlpha = true
		},
		TabPanelTabListButton = {
			InactiveCol = Clear,
			ActiveCol = Clear,
			TextInheritsParentAlpha = false
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
	Hint = {
		Default = {
			Colour = SGUI.ColourWithAlpha( DarkButton, 0.8 ),
			TextColour = BrightText
		},
		Danger = {
			FlairColour = Danger
		},
		Warning = {
			FlairColour = Warning
		},
		Info = {
			FlairColour = Info
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
	Notification = {
		Default = {
			TextColour = SGUI.ColourWithAlpha( BrightText, 2 ),
			FlairIconColour = SGUI.ColourWithAlpha( BrightText, 2 ),
			Colour = SGUI.ColourWithAlpha( DarkButton, 0.8 )
		},
		Danger = {
			FlairIconText = SGUI.Icons.Ionicons.AlertCircled,
			FlairColour = Danger
		},
		Warning = {
			FlairIconText = SGUI.Icons.Ionicons.Alert,
			FlairColour = Warning
		},
		Info = {
			FlairIconText = SGUI.Icons.Ionicons.InformationCircled,
			FlairColour = Info
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
		},
		RadioBackground = {
			Colour = Clear
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
		},
		Horizontal = {
			TabBackgroundColour = Clear,
			PanelColour = HorizontalTabBackground,
			Colour = Clear
		}
	},
	TabPanelButton = {
		Default = {
			Font = Fonts.kAgencyFB_Small,
			ActiveCol = WindowBackground,
			InactiveCol = DarkButton,
			TextColour = BrightText
		},
		Horizontal = {
			Font = Fonts.kAgencyFB_Small,
			ActiveCol = HorizontalTabBackground,
			InactiveCol = DarkButton,
			TextColour = BrightText
		}
	},
	TextEntry = {
		Default = {
			FocusColour = Colour( 0.35, 0.35, 0.35, 1 ),
			DarkColour = Colour( 0.4, 0.4, 0.4, 1 ),
			HighlightColour = Colour( 1, 0.4, 0, 0.5 ),
			PlaceholderTextColour = SGUI.ColourWithAlpha( BrightText, 0.8 ),
			TextColour = BrightText,
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

SGUI.SkinManager:RegisterSkin( "Default", Skin )
