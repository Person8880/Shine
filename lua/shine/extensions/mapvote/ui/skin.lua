--[[
	Skin for the map vote UI elements.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local HeaderAlpha = 0.25
local MapTileHeaderAlpha = 0.75
local MapTileImageColour = Colour( 0.5, 0.5, 0.5, 1 )
local MapTileBackgroundAlpha = 0.15

local HeaderVariations = {
	Alien = {
		Colour = Colour( 1, 0.75, 0, HeaderAlpha )
	},
	Marine = {
		Colour = Colour( 0, 0.75, 1, HeaderAlpha )
	}
}
local ProgressWheelBaseParams = {
	AnimateLoading = true,
	WheelTexture = {
		Texture = "ui/shine/wheel.tga",
		W = 128,
		H = 128
	},
	SpinRate = -math.pi * 2
}

return {
	Button = {
		CloseButton = {
			InactiveCol = Colour( 1, 1, 1, 1 ),
			ActiveCol = Colour( 1, 1, 1, 1 ),
			TextColour = Colour( 1, 1, 1, 1 ),
			Shader = SGUI.Shaders.Invisible
		},
		ConfigButton = {
			InactiveCol = Colour( 0.4, 0.4, 0.4, 1 ),
			ActiveCol = Colour( 0.4, 0.4, 0.4, 1 ),
			TextColour = Colour( 1, 1, 1, 1 ),
			Shader = "shaders/GUIBasic.surface_shader"
		},
		MenuButton = {
			TextColour = Colour( 1, 1, 1 ),
			InactiveCol = Colour( 0.25, 0.25, 0.25, 1 ),
			ActiveCol = Colour( 0.4, 0.4, 0.4, 1 ),
			TextAlignment = SGUI.LayoutAlignment.MIN,
			IconAlignment = SGUI.LayoutAlignment.MIN,
			Padding = Units.Spacing( Units.GUIScaled( 8 ), 0, Units.GUIScaled( 8 ), 0 )
		},
		ShowOverviewButton = {
			TextColour = Colour( 1, 1, 1, 1 ),
			IconAutoFont = {
				Family = SGUI.FontFamilies.Ionicons,
				Size = Units.GUIScaled( 32 )
			},
			Shader = SGUI.Shaders.Invisible
		}
	},
	Image = {
		PreviewImage = {
			InactiveCol = MapTileImageColour,
			ActiveCol = Colour( 1, 1, 1, 1 ),
			Colour = MapTileImageColour
		}
	},
	Label = {
		Default = {
			Colour = Colour( 1, 1, 1, 1 )
		},
		MapTileLabel = {
			Colour = Colour( 1, 1, 1, 1 ),
			TextAlignmentX = GUIItem.Align_Center,
			UseAlignmentCompensation = true
		},
		MapTileVoteCountWinner = {
			Colour = Colour( 0, 1, 0, 1 ),
			TextAlignmentX = GUIItem.Align_Center,
			UseAlignmentCompensation = true
		},
		MapTileVoteCountTied = {
			Colour = Colour( 1, 1, 0, 1 ),
			TextAlignmentX = GUIItem.Align_Center,
			UseAlignmentCompensation = true
		},
		HeaderLabel = {
			Colour = Colour( 1, 1, 1, 1 ),
			Shadow = {
				Colour = Colour( 0, 0, 0, 0.75 )
			}
		},
		CountdownTimeRunningOut = {
			Colour = Colour( 1, 0, 0, 1 ),
			Shadow = {
				Colour = Colour( 0, 0, 0, 0.75 )
			}
		}
	},
	MapVoteMenu = {
		Default = {
			Colour = Colour( 1, 1, 1, 1 )
		}
	},
	MapTile = {
		Default = {
			TextColour = Colour( 1, 1, 1, 1 ),
			IconColour = Colour( 0, 1, 0, 1 ),
			InactiveCol = Colour( 0, 0, 0, 1 ),
			MapNameAutoFont = {
				Family = "kAgencyFB",
				Size = Units.GUIScaled( 41 )
			},
			VoteCounterAutoFont = {
				Family = "kAgencyFB",
				Size = Units.GUIScaled( 41 )
			},
			IconShadow = {
				Colour = Colour( 0, 0, 0, 0.75 )
			},
			Shader = SGUI.Shaders.Invisible,
			States = {
				Display = {
					ActiveCol = Colour( 0, 0, 0, 1 ),
					InactiveCol = Colour( 0, 0, 0, 1 )
				}
			}
		},
		SmallerFonts = {
			MapNameAutoFont = {
				Family = "kAgencyFB",
				Size = Units.GUIScaled( 27 )
			},
			VoteCounterAutoFont = {
				Family = "kAgencyFB",
				Size = Units.GUIScaled( 27 )
			},
		}
	},
	Menu = {
		Default = {
			Colour = Colour( 0.25, 0.25, 0.25, 1 )
		}
	},
	ProgressWheel = {
		Alien = table.ShallowMerge( ProgressWheelBaseParams, {
			Colour = Colour( 1, 0.75, 0, 1 )
		} ),
		Marine = table.ShallowMerge( ProgressWheelBaseParams, {
			Colour = Colour( 0, 0.75, 1, 1 )
		} )
	},
	Row = table.ShallowMerge( HeaderVariations, {
		LoadingIndicatorContainer = {
			Colour = Colour( 0, 0, 0, 0.25 )
		},
		MapTileHeader = {
			Colour = Colour( 0, 0, 0, MapTileHeaderAlpha )
		}
	} ),
	Column = table.ShallowMerge( HeaderVariations, {
		MapTileGrid = {
			Colour = Colour( 0.75, 0.75, 0.75, MapTileBackgroundAlpha )
		}
	} )
}
