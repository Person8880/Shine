--[[
	Defines the notification that appears on screen when a map vote is in-progress.
]]

local Locale = Shine.Locale
local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local CalculateTextSize = GUI.CalculateTextSize
local Ceil = math.ceil
local SharedTime = Shared.GetTime
local StringDigitalTime = string.DigitalTime
local StringGMatch = string.gmatch
local TableConcat = table.concat

local BackgroundAlpha = 0.75
local KeyTextureSize = 84
local KeyTextureMaxTextWidth = Ceil( ( 150 / 256 ) * KeyTextureSize )
local LargePadding = Units.GUIScaled( 16 )
local SmallPadding = Units.GUIScaled( 8 )
local DefaultFontSize = 29

local DefaultLabelFont = {
	Family = SGUI.FontFamilies.MicrogrammaDBolExt,
	Size = Units.GUIScaled( DefaultFontSize )
}

local Skin = {
	Row = {
		Default = {
			Colour = Colour( 0.3, 0.3, 0.3, BackgroundAlpha ),
			InheritsParentAlpha = true
		}
	},
	Column = {
		Default = {
			Colour = Colour( 0.1, 0.1, 0.1, BackgroundAlpha ),
			InheritsParentAlpha = true
		}
	},
	Image = {
		Default = {
			InheritsParentAlpha = true
		},
		Alien = {
			Colour = Colour( 1, 0.75, 0, 1 / BackgroundAlpha )
		},
		Marine = {
			Colour = Colour( 0, 0.75, 1, 1 / BackgroundAlpha )
		}
	},
	Label = {
		Default = {
			AutoFont = DefaultLabelFont,
			Colour = Colour( 1, 1, 1, 1 / BackgroundAlpha ),
			InheritsParentAlpha = true
		},
		CountdownTimeRunningOut = {
			Colour = Colour( 1, 0, 0, 1 / BackgroundAlpha )
		},
		Alien = {
			Colour = Colour( 1, 0.75, 0, 1 / BackgroundAlpha )
		},
		Marine = {
			Colour = Colour( 0, 0.75, 1, 1 / BackgroundAlpha )
		}
	},
	MapVoteNotification = {
		Default = {
			Shader = SGUI.Shaders.Invisible
		}
	}
}

local MapVoteNotification = SGUI:DefineControl( "MapVoteNotification", "Row" )

SGUI.AddProperty( MapVoteNotification, "Keybind" )
SGUI.AddProperty( MapVoteNotification, "EndTime" )

function MapVoteNotification:Initialise()
	Controls.Row.Initialise( self )

	self:SetSkin( Skin )

	local NiceKeyNames = {
		NumPadAdd = "NP +",
		NumPadPeriod = "NP .",
		NumPadEnter = "NP Enter",
		NumPadMultiply = "NP *",
		NumPadDivide = "NP /",
		NumPadEquals = "NP =",
		NumPadSubtract = "NP -",
		Comma = ",",
		Period = ".",
		Grave = "`",
		Backslash = "\\",
		Apostrophe = "'",
		Minus = "-",
		Equals = "=",
		Semicolon = ";",
		LeftBracket = "[",
		RightBracket = "]",
		Slash = "/"
	}
	for i = 0, 9 do
		NiceKeyNames[ "NumPad"..i ] = "NP "..i
	end

	local function SplitIntoWords( Keybind )
		local Words = {}
		for Segment in StringGMatch( Keybind, "(%u[^%u]*)" ) do
			Words[ #Words + 1 ] = Segment
		end
		return TableConcat( Words, "\n" )
	end

	local function GetKeyBindDisplayText( Keybind )
		return NiceKeyNames[ Keybind ] or SplitIntoWords( Keybind )
	end

	local function ComputeFontForKeybind( Keybind )
		if not Keybind then
			return DefaultLabelFont
		end

		Keybind = GetKeyBindDisplayText( Keybind )

		local Font, Scale = SGUI.FontManager.GetFont( SGUI.FontFamilies.MicrogrammaDBolExt, DefaultFontSize )
		local Width = CalculateTextSize( Font, Keybind ).x

		if Width > KeyTextureMaxTextWidth then
			return {
				Family = SGUI.FontFamilies.MicrogrammaDBolExt,
				Size = Units.GUIScaled( DefaultFontSize * ( KeyTextureMaxTextWidth / Width ) )
			}
		end

		return DefaultLabelFont
	end

	self.Elements = SGUI:BuildTree( {
		Parent = self,
		{
			ID = "KeybindBackground",
			Class = "Row",
			Props = {
				Fill = false,
				AutoSize = Units.UnitVector( Units.Auto(), Units.Auto() ),
				Padding = Units.Spacing( LargePadding, LargePadding, LargePadding, LargePadding )
			},
			Children = {
				{
					ID = "KeybindImage",
					Class = "Image",
					Props = {
						Texture = "ui/keyboard_key_small.dds",
						BlendTechnique = GUIItem.Add,
						AutoSize = Units.UnitVector( Units.GUIScaled( 84 ), Units.GUIScaled( 84 ) ),
					},
					Children = {
						{
							Type = "Layout",
							Class = "Vertical",
							Props = {
								Fill = true
							},
							Children = {
								{
									ID = "KeybindLabel",
									Class = "Label",
									Props = {
										Alignment = SGUI.LayoutAlignment.CENTRE,
										CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
										Margin = Units.Spacing( 0, Units.GUIScaled( -16 ), 0, 0 ),
										TextAlignmentX = GUIItem.Align_Center,
										UseAlignmentCompensation = true
									},
									Bindings = {
										{
											From = {
												Element = self,
												Property = "Keybind"
											},
											To = {
												Property = "Text",
												Filter = function( Keybind ) return not not Keybind end,
												Transformer = GetKeyBindDisplayText
											}
										},
										{
											From = {
												Element = self,
												Property = "Keybind"
											},
											To = {
												Property = "AutoFont",
												Transformer = ComputeFontForKeybind
											}
										}
									}
								}
							}
						}
					}
				}
			}
		},
		{
			Class = "Column",
			Props = {
				Fill = false,
				AutoSize = Units.UnitVector( Units.Auto(), Units.Percentage( 100 ) ),
				Padding = Units.Spacing( LargePadding, LargePadding, LargePadding, LargePadding )
			},
			Children = {
				{
					Class = "Label",
					Props = {
						Text = Locale:GetPhrase( "mapvote", "MAP_VOTE_MENU_TITLE" ),
						Margin = Units.Spacing( 0, 0, 0, SmallPadding ),
						Alignment = SGUI.LayoutAlignment.CENTRE
					}
				},
				{
					ID = "CountdownLabel",
					Class = "Label",
					Props = {
						Text = "00:00",
						Alignment = SGUI.LayoutAlignment.CENTRE
					}
				}
			}
		}
	} )
end

function MapVoteNotification:SetLayer( Layer )
	-- Always display underneath other UI elements.
	return self.BaseClass.SetLayer( self, 0 )
end

function MapVoteNotification:GetTeamVariation()
	local Player = Client.GetLocalPlayer()
	return Player and Player:isa( "Alien" ) and "Alien" or "Marine", Player and Player:GetTeamNumber() or 0
end

function MapVoteNotification:UpdateCountdown()
	local TimeLeft = Ceil( self.EndTime - SharedTime() )
	self.Elements.CountdownLabel:SetText( StringDigitalTime( TimeLeft ) )

	if TimeLeft <= 10 and self.Elements.CountdownLabel:GetStyleName() ~= "CountdownTimeRunningOut" then
		self.Elements.CountdownLabel:SetStyleName( "CountdownTimeRunningOut" )
	end
end

function MapVoteNotification:UpdateTeamVariation()
	local TeamVariation, TeamNumber = self:GetTeamVariation()
	self.Elements.KeybindImage:SetStyleName( TeamVariation )
	self.Elements.KeybindLabel:SetStyleName( TeamVariation )

	local W, H = SGUI.GetScreenSize()
	if TeamNumber == 1 or TeamNumber == 2 then
		-- If on a playing team, position the element in the top-right to avoid it being too distracting.
		self:SetPos( Vector2( W * 0.95 - self:GetSize().x, H * 0.2 ) )
	else
		-- If not on a playing team, show it at the bottom-centre to make it more noticeable.
		self:SetPos( Vector2( W * 0.5 - self:GetSize().x * 0.5, H * 0.9 - self:GetSize().y ) )
	end
end

function MapVoteNotification:FadeIn()
	self:SetIsVisible( true )
	self:ApplyTransition( {
		Type = "Alpha",
		StartValue = 0,
		EndValue = 1,
		Duration = 0.3
	} )
	self:UpdateTeamVariation()
end

function MapVoteNotification:FadeOut( Callback )
	self.FadingOut = true

	self:ApplyTransition( {
		Type = "Alpha",
		EndValue = 0,
		Duration = 0.3,
		Callback = function()
			self:SetIsVisible( false )
			self.FadingOut = false
			if Callback then
				-- Call after Think exits to avoid destroying GUIItems that are in use.
				SGUI:AddPostEventAction( Callback )
			end
		end
	} )
end

function MapVoteNotification:Hide( Callback )
	if not self:GetIsVisible() then
		if Callback then
			Callback()
		end
		return
	end

	self:FadeOut( Callback )
end

function MapVoteNotification:Think( DeltaTime )
	self:UpdateCountdown()
	return self.BaseClass.Think( self, DeltaTime )
end

return MapVoteNotification
