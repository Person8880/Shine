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
		Colour = Colour( 1, 0.75, 0, HeaderAlpha ),
		InheritsParentAlpha = true
	},
	Marine = {
		Colour = Colour( 0, 0.75, 1, HeaderAlpha ),
		InheritsParentAlpha = true
	}
}
local ProgressWheelBaseParams = {
	AnimateLoading = true,
	WheelTexture = {
		Texture = "ui/shine/wheel.tga",
		W = 128,
		H = 128
	},
	SpinRate = -math.pi * 2,
	InheritsParentAlpha = true
}

return {
	Button = {
		CloseButton = {
			InactiveCol = Colour( 1, 1, 1, 1 ),
			ActiveCol = Colour( 1, 1, 1, 1 ),
			TextColour = Colour( 1, 1, 1, 1 / HeaderAlpha ),
			TextInheritsParentAlpha = true,
			InheritsParentAlpha = true,
			Shader = SGUI.Shaders.Invisible
		},
		ConfigButton = {
			InactiveCol = Colour( 0.4, 0.4, 0.4, 1 / HeaderAlpha ),
			ActiveCol = Colour( 0.4, 0.4, 0.4, 1 / HeaderAlpha ),
			TextColour = Colour( 1, 1, 1, 1 / HeaderAlpha ),
			TextInheritsParentAlpha = true,
			InheritsParentAlpha = true,
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
			TextInheritsParentAlpha = true,
			InheritsParentAlpha = true,
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
			Colour = Colour( 1, 1, 1, 1 / MapTileHeaderAlpha ),
			InheritsParentAlpha = true,
			TextAlignmentX = GUIItem.Align_Center,
			UseAlignmentCompensation = true
		},
		MapTileVoteCountWinner = {
			Colour = Colour( 0, 1, 0, 1 / MapTileHeaderAlpha ),
			InheritsParentAlpha = true,
			TextAlignmentX = GUIItem.Align_Center,
			UseAlignmentCompensation = true
		},
		MapTileVoteCountTied = {
			Colour = Colour( 1, 1, 0, 1 / MapTileHeaderAlpha ),
			InheritsParentAlpha = true,
			TextAlignmentX = GUIItem.Align_Center,
			UseAlignmentCompensation = true
		},
		HeaderLabel = {
			Colour = Colour( 1, 1, 1, 1 / HeaderAlpha ),
			Shadow = {
				Colour = Colour( 0, 0, 0, 0.75 / HeaderAlpha )
			},
			InheritsParentAlpha = true
		},
		CountdownTimeRunningOut = {
			Colour = Colour( 1, 0, 0, 1 / HeaderAlpha ),
			Shadow = {
				Colour = Colour( 0, 0, 0, 0.75 / HeaderAlpha )
			},
			InheritsParentAlpha = true
		}
	},
	MapVoteMenu = {
		Default = {
			Colour = Colour( 1, 1, 1, 1 )
		}
	},
	MapTile = {
		Default = {
			TextColour = Colour( 1, 1, 1, 1 / MapTileHeaderAlpha ),
			IconColour = Colour( 0, 1, 0, 1 ),
			InactiveCol = Colour( 0, 0, 0, 1 / MapTileBackgroundAlpha ),
			TextInheritsParentAlpha = true,
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
			InheritsParentAlpha = true,
			Shader = SGUI.Shaders.Invisible,
			States = {
				Display = {
					InheritsParentAlpha = false,
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
			Colour = Colour( 1, 0.75, 0, 1 / 0.25 )
		} ),
		Marine = table.ShallowMerge( ProgressWheelBaseParams, {
			Colour = Colour( 0, 0.75, 1, 1 / 0.25 )
		} )
	},
	Row = table.ShallowMerge( HeaderVariations, {
		LoadingIndicatorContainer = {
			Colour = Colour( 0, 0, 0, 0.25 ),
			InheritsParentAlpha = true
		},
		MapTileHeader = {
			Colour = Colour( 0, 0, 0, MapTileHeaderAlpha ),
			InheritsParentAlpha = true
		}
	} ),
	Column = table.ShallowMerge( HeaderVariations, {
		MapTileGrid = {
			Colour = Colour( 0.75, 0.75, 0.75, MapTileBackgroundAlpha ),
			InheritsParentAlpha = true
		}
	} )
}
