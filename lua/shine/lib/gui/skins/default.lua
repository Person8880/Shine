--[[
	Default Shine GUI skin.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local WindowBackground = Colour( 0.5, 0.5, 0.5, 1 )
local HorizontalTabBackground = Colour( 0.4, 0.4, 0.4, 1 )
local DarkButton = Colour( 0.2, 0.2, 0.2, 1 )
local ButtonHighlight = Colour( 0.8, 0.5, 0.1, 1 )
local BrightText = Colour( 1, 1, 1, 1 )
local MutedText = Colour( 0.9, 0.9, 0.9, 1 )
local Clear = Colour( 0, 0, 0, 0 )
local SliderDarkLineColour = Colour( 0.2, 0.2, 0.2, 1 )

local Danger = Colour( 1, 0, 0 )
local Warning = Colour( 1, 0.6, 0 )
local Info = Colour( 0, 0.5, 1 )

local SuccessButton = Colour( 0.1, 0.6, 0.1, 1 )
local DangerButton = Colour( 1, 0.2, 0.1, 1 )
local CategoryButton = Colour( 0.3, 0.3, 0.3, 1 )
local OrangeButtonHighlight = Colour( 1, 0.4, 0, 1 )

local DefaultButton = {
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
}
local DropdownPadding = Units.Spacing( Units.HighResScaled( 4 ), 0, Units.HighResScaled( 4 ), 0 )

local Skin = {
	Button = {
		Default = DefaultButton,
		CloseButton = {
			ActiveCol = Colour( 0.7, 0.2, 0.2, 1 ),
			InactiveCol = Colour( 0.5, 0.2, 0.2, 1 )
		},
		MenuButton = {
			InactiveCol = Colour( 0.25, 0.25, 0.25, 1 )
		},
		CategoryPanelButton = {
			Font = Fonts.kAgencyFB_Small,
			ActiveCol = OrangeButtonHighlight,
			InactiveCol = CategoryButton,
			States = {
				Collapsed = {
					InactiveCol = SGUI.ColourWithAlpha( CategoryButton, 0.85 )
				}
			}
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
		},
		DropdownButton = {
			Padding = DropdownPadding,
			TextAlignment = SGUI.LayoutAlignment.MIN,
			IconAlignment = SGUI.LayoutAlignment.MIN
		},
		TabPanelOverflowMenuButton = {
			TextAlignment = SGUI.LayoutAlignment.MIN,
			IconAlignment = SGUI.LayoutAlignment.MIN,
			Padding = Units.Spacing( Units.HighResScaled( 8 ), 0, 0, 0 )
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
			Font = Fonts.kAgencyFB_Small,
			States = {
				Disabled = {
					BackgroundColour = SGUI.ColourWithAlpha( DarkButton, 0.5 ),
					CheckedColour = SGUI.ColourWithAlpha( ButtonHighlight, 0.5 ),
					TextColour = SGUI.ColourWithAlpha( BrightText, 0.5 )
				}
			}
		}
	},
	Column = {
		Default = {
			Colour = WindowBackground
		}
	},
	ColourLabel = {
		Default = {
			Font = Fonts.kAgencyFB_Small
		}
	},
	Dropdown = {
		Default = table.ShallowMerge( DefaultButton, {
			Padding = DropdownPadding,
			MenuClosedIcon = SGUI.Icons.Ionicons.ArrowDownB,
			MenuOpenIcon = SGUI.Icons.Ionicons.ArrowUpB
		} )
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
		},
		SuccessLabel = {
			Colour = Colour( 0.1, 1, 0.1, 1 )
		},
		DangerLabel = {
			Colour = Colour( 1, 0.2, 0.1, 1 )
		},
		InfoLabel = {
			Colour = SGUI.SaturateColour( Info, 0.5 )
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
			ActiveCol = OrangeButtonHighlight,
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
	Modal = {
		Default = {
			BoxShadow = {
				BlurRadius = 8,
				Colour = Colour( 0, 0, 0, 0.75 )
			},
			Colour = WindowBackground
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
			ProgressColour = OrangeButtonHighlight,
			BorderSize = Vector2( 0, 0 )
		}
	},
	ProgressWheel = {
		Default = {
			WheelTexture = {
				Texture = "ui/shine/wheel.tga",
				W = 128,
				H = 128
			},
			Colour = OrangeButtonHighlight
		}
	},
	Radio = {
		Default = {
			BackgroundColour = Clear
		}
	},
	Row = {
		Default = {
			Colour = WindowBackground
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
			DarkLineColour = SliderDarkLineColour,
			HandleColour = ButtonHighlight,
			LineColour = ButtonHighlight,
			TextColour = BrightText,
			LineHeightMultiplier = 0.15,
			States = {
				Disabled = {
					DarkLineColour = SGUI.ColourWithAlpha( SliderDarkLineColour, 0.5 ),
					HandleColour = SGUI.ColourWithAlpha( ButtonHighlight, 0.5 ),
					LineColour = SGUI.ColourWithAlpha( ButtonHighlight, 0.5 ),
					TextColour = SGUI.ColourWithAlpha( BrightText, 0.5 )
				}
			}
		}
	},
	Switch = {
		Default = {
			ActiveBackgroundColour = SuccessButton,
			InactiveBackgroundColour = DarkButton,
			KnobColour = Colour( 0.6, 0.6, 0.6, 1 ),
			States = {
				Disabled = {
					ActiveBackgroundColour = SGUI.ColourWithAlpha( SuccessButton, 0.5 ),
					InactiveBackgroundColour = SGUI.ColourWithAlpha( DarkButton, 0.5 ),
					KnobColour = Colour( 0.6, 0.6, 0.6, 0.5 )
				},
				Active = {
					KnobColour = BrightText
				}
			}
		}
	},
	TabPanel = {
		Default = {
			TabBackgroundColour = DarkButton,
			PanelColour = WindowBackground,
			Colour = DarkButton
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
			ActiveCol = ButtonHighlight,
			InactiveCol = DarkButton,
			TextColour = MutedText,
			States = {
				Highlighted = {
					InactiveCol = CategoryButton,
					TextColour = BrightText
				},
				Selected = {
					TextColour = BrightText
				}
			}
		},
		Horizontal = {
			Font = Fonts.kAgencyFB_Small,
			ActiveCol = HorizontalTabBackground,
			InactiveCol = DarkButton,
			TextColour = MutedText,
			States = {
				Highlighted = {
					InactiveCol = CategoryButton,
					TextColour = BrightText
				},
				Selected = {
					TextColour = BrightText
				}
			}
		}
	},
	TextEntry = {
		Default = {
			FocusColour = Colour( 0.35, 0.35, 0.35, 1 ),
			DarkColour = Colour( 0.4, 0.4, 0.4, 1 ),
			HighlightColour = SGUI.ColourWithAlpha( OrangeButtonHighlight, 0.5 ),
			PlaceholderTextColour = SGUI.ColourWithAlpha( BrightText, 0.8 ),
			TextColour = BrightText,
			BorderColour = Colour( 0.3, 0.3, 0.3, 1 ),
			BorderSize = Vector2( 1, 1 ),
			States = {
				Focus = {
					BorderColour = OrangeButtonHighlight
				}
			}
		},
		SliderTextBox = {
			FocusColour = Clear,
			DarkColour = Clear,
			BorderSize = Vector2( 0, 0 ),
			BorderColour = Clear,
			States = {
				Focus = {
					BorderColour = Clear
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
