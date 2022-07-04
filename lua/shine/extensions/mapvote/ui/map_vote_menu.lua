--[[
	Defines the UI for the map vote menu.

	This displays a grid of map tiles, each with an image of the map in question,
	the name of the map, its number of current votes, and the ability to show the
	map's overview image on hover.

	Additionally, the time left to vote and the current map are displayed at the top.
]]

local Ceil = math.ceil
local Floor = math.floor
local Max = math.max
local Min = math.min
local SharedTime = Shared.GetTime
local Sqrt = math.sqrt
local StringDigitalTime = string.DigitalTime
local StringFormat = string.format

local Locale = Shine.Locale
local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local MapDataRepository = require "shine/extensions/mapvote/map_data_repository"
local MapTile = require "shine/extensions/mapvote/ui/map_vote_menu_tile"
local TextureLoader = require "shine/lib/gui/texture_loader"

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

local Skin = {
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
			Shader = SGUI.Shaders.Invisible
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

local MapVoteMenu = SGUI:DefineControl( "MapVoteMenu", "Panel" )

SGUI.AddProperty( MapVoteMenu, "CloseOnClick", true )
SGUI.AddProperty( MapVoteMenu, "CurrentMap" )
SGUI.AddProperty( MapVoteMenu, "EndTime" )
SGUI.AddProperty( MapVoteMenu, "LoadModPreviews", true )
SGUI.AddProperty( MapVoteMenu, "Logger" )
SGUI.AddProperty( MapVoteMenu, "MaxVoteChoices", 8 )
SGUI.AddProperty( MapVoteMenu, "MultiSelect", false )

function MapVoteMenu:Initialise()
	Controls.Panel.Initialise( self )
	self:SetSkin( Skin )

	self:SetAlpha( 0 )
	self.Background:SetShader( SGUI.Shaders.Invisible )
	self.MapTiles = {}
	self.Logger = Shine.Objects.Logger( Shine.Objects.Logger.LogLevel.INFO, Shared.Message )
	self.TitleBarHeight = Units.GUIScaled( 32 ):GetValue()

	local TeamVariation = self:GetTeamVariation()
	local SmallPadding = Units.GUIScaled( 8 )

	local function GetSubTitle()
		if self:GetMultiSelect() then
			return Locale:GetInterpolatedPhrase( "mapvote", "MAP_VOTE_MENU_MULTIPLE_CHOICE_DESCRIPTION", {
				MaxVoteChoices = self:GetMaxVoteChoices()
			} )
		end

		return Locale:GetPhrase( "mapvote", "MAP_VOTE_MENU_SINGLE_CHOICE_DESCRIPTION" )
	end

	self.Elements = SGUI:BuildTree( {
		Parent = self,
		GlobalProps = {
			Skin = Skin
		},
		{
			Type = "Layout",
			Class = "Vertical",
			Children = {
				{
					ID = "TitleBox",
					Class = "Column",
					Props = {
						AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, Units.Auto.INSTANCE + Units.GUIScaled( 16 ) ),
						StyleName = TeamVariation
					},
					Children = {
						{
							Class = "Label",
							Props = {
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoFont = {
									Family = SGUI.FontFamilies.MicrogrammaDBolExt,
									Size = Units.GUIScaled( 96 )
								},
								Text = Locale:GetPhrase( "mapvote", "MAP_VOTE_MENU_TITLE" ),
								StyleName = "HeaderLabel"
							}
						},
						{
							ID = "CurrentMapLabel",
							Class = "Label",
							Props = {
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoFont = {
									Family = SGUI.FontFamilies.MicrogrammaDBolExt,
									Size = Units.GUIScaled( 29 )
								},
								Text = Shared.GetMapName(),
								StyleName = "HeaderLabel"
							}
						},
						{
							Class = "Label",
							Props = {
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoFont = {
									Family = SGUI.FontFamilies.MicrogrammaDBolExt,
									Size = Units.GUIScaled( 29 )
								},
								StyleName = "HeaderLabel",
							},
							Bindings = {
								{
									From = {
										Element = self,
										Property = "MultiSelect"
									},
									To = {
										Property = "Text",
										Transformer = GetSubTitle
									}
								},
								{
									From = {
										Element = self,
										Property = "MaxVoteChoices"
									},
									To = {
										Property = "Text",
										Transformer = GetSubTitle
									}
								}
							}
						}
					}
				},
				{
					ID = "InformationBox",
					Class = "Row",
					Props = {
						AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, Units.Auto.INSTANCE + SmallPadding ),
						Margin = Units.Spacing( 0, SmallPadding, 0, 0 ),
						Padding = Units.Spacing( SmallPadding, 0, SmallPadding, 0 ),
						StyleName = TeamVariation
					},
					Children = {
						{
							ID = "CountdownLabel",
							Class = "Label",
							Props = {
								Alignment = SGUI.LayoutAlignment.CENTRE,
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoFont = {
									Family = SGUI.FontFamilies.MicrogrammaDBolExt,
									Size = Units.GUIScaled( 59 )
								},
								StyleName = "HeaderLabel"
							}
						}
					}
				},
				{
					ID = "MapTileGrid",
					Class = "Column",
					Props = {
						Fill = true,
						Margin = Units.Spacing( 0, SmallPadding, 0, 0 ),
						Padding = Units.Spacing( SmallPadding, SmallPadding, SmallPadding, SmallPadding ),
						StyleName = "MapTileGrid"
					}
				}
			}
		}
	} )

	self.Elements.MapTileGridLayout = self.Elements.MapTileGrid.Layout
	self.Elements.MapTileGridLayout:AddPropertyChangeListener( "Size", function( Layout, Size )
		self:SetupTileGrid()
	end )

	self:AddCloseButton( self )

	local ConfigButton = SGUI:BuildTree( {
		Parent = self,
		{
			ID = "ConfigButton",
			Class = "Button",
			Props = {
				AutoSize = Units.UnitVector( self.TitleBarHeight, self.TitleBarHeight ),
				PositionType = SGUI.PositionType.ABSOLUTE,
				LeftOffset = Units.Percentage.ONE_HUNDRED - self.TitleBarHeight * 2,
				Text = SGUI.Icons.Ionicons.GearB,
				OpenMenuOnClick = function( ConfigButton )
					local ButtonPadding = Units.MultipleOf2( SmallPadding ):GetValue()

					return {
						MenuPos = Vector2( 0, self.TitleBarHeight ),
						Size = Units.Absolute( self.TitleBarHeight + ButtonPadding ),
						Populate = function( Menu )
							Menu:SetFontScale( SGUI.FontManager.GetFont( "kAgencyFB", 27 ) )

							local IconFont, IconScale = SGUI.FontManager.GetFont( SGUI.FontFamilies.Ionicons, 32 )

							Menu:AddButton(
								Locale:GetPhrase( "mapvote", "MAP_VOTE_MENU_USE_VOTE_MENU_BUTTON" ),
								function()
									self:OnPropertyChanged( "UseVoteMenu", true )
									Menu:Destroy()
								end
							):SetIcon( SGUI.Icons.Ionicons.ArrowShrink, IconFont, IconScale )

							Menu:AddButton(
								Locale:GetPhrase(
									"mapvote",
									self.LoadModPreviews and "MAP_VOTE_MENU_DISABLE_PREVIEWS"
										or "MAP_VOTE_MENU_ENABLE_PREVIEWS"
								),
								function()
									self:SetLoadModPreviews( not self.LoadModPreviews )
									Menu:Destroy()
								end
							):SetIcon(
								SGUI.Icons.Ionicons[ self.LoadModPreviews and "EyeDisabled" or "Eye" ],
								IconFont,
								IconScale
							)

							if not self:GetMultiSelect() then
								Menu:AddButton(
									Locale:GetPhrase(
										"mapvote",
										self.CloseOnClick and "MAP_VOTE_MENU_DISABLE_CLOSE_ON_CLICK"
											or "MAP_VOTE_MENU_ENABLE_CLOSE_ON_CLICK"
									),
									function()
										self:SetCloseOnClick( not self.CloseOnClick )
										Menu:Destroy()
									end
								):SetIcon(
									SGUI.Icons.Ionicons[ self.CloseOnClick and "Pin" or "Close" ],
									IconFont,
									IconScale
								)
							end

							Menu:AutoSizeButtonIcons()
							Menu:Resize()

							local MenuOffset = Vector2( self.TitleBarHeight - Menu:GetSize().x, self.TitleBarHeight )
							Menu:SetPos( ConfigButton:GetScreenPos() + MenuOffset )
						end
					}
				end,
				StyleName = "CloseButton"
			},
			Bindings = {
				{
					From = {
						Element = "ConfigButton",
						Property = "Menu"
					},
					To = {
						Property = "StyleName",
						Transformer = function( Menu )
							return Menu and "ConfigButton" or "CloseButton"
						end
					}
				}
			}
		}
	} ).ConfigButton

	ConfigButton:SetFontScale( SGUI.FontManager.GetFontForAbsoluteSize(
		SGUI.FontFamilies.Ionicons,
		self.TitleBarHeight
	) )
end

local function IsAlien( Player )
	return Player:isa( "Alien" ) or ( Player.GetTeamNumber and Player:GetTeamNumber() == kTeam2Index )
end

function MapVoteMenu:GetTeamVariation()
	local Player = Client.GetLocalPlayer()
	return Player and IsAlien( Player ) and "Alien" or "Marine"
end

function MapVoteMenu:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() or self.FadingOut then return end

	if Key == InputKey.Escape and Down then
		self:Close()
		return true
	end

	return Controls.Panel.PlayerKeyPress( self, Key, Down )
end

function MapVoteMenu:FadeIn()
	SGUI:EnableMouse( true, self )

	self.FadingOut = false
	self:SetIsVisible( true )
	self:ApplyTransition( {
		Type = "Alpha",
		StartValue = 0,
		EndValue = 1,
		Duration = 0.3
	} )

	local TeamVariation = self:GetTeamVariation()
	self.Elements.TitleBox:SetStyleName( TeamVariation )
	self.Elements.InformationBox:SetStyleName( TeamVariation )

	for i = 1, #self.MapTiles do
		self.MapTiles[ i ]:SetTeamVariation( TeamVariation )
	end
end

local function OnFadeOutComplete( self )
	self:SetIsVisible( false )
	self.FadingOut = false
	self:OnClose()
	if self.FadeOutCallback then
		-- Call after Think exits to avoid destroying GUIItems that are in use.
		SGUI:AddPostEventAction( self.FadeOutCallback )
	end
end

function MapVoteMenu:FadeOut( Callback )
	self.FadingOut = true
	self.FadeOutCallback = Callback

	self:ApplyTransition( {
		Type = "Alpha",
		EndValue = 0,
		Duration = 0.3,
		Callback = OnFadeOutComplete
	} )
end

function MapVoteMenu:PreClose()

end

function MapVoteMenu:OnClose()

end

function MapVoteMenu:Close( Callback )
	SGUI:EnableMouse( false, self )
	self:PreClose()

	if not self:GetIsVisible() then
		if Callback then
			Callback()
		end
		return
	end

	self:FadeOut( Callback )
end

function MapVoteMenu:SetCurrentMapName( MapName )
	self.Elements.CurrentMapLabel:SetText(
		Locale:GetInterpolatedPhrase( "mapvote", "MAP_VOTE_MENU_CURRENT_MAP", { MapName = MapName } )
	)
end

local function OnPreviewImageLoaded( self, MapName, TextureName, Err )
	if not SGUI.IsValid( self ) then
		if not Err then
			TextureLoader.Free( TextureName )
		end
		return
	end

	local Tile = self.MapTiles[ MapName ]
	if Err then
		self.Logger:Debug( "Failed to load preview image for %s: %s", MapName, Err )
		if SGUI.IsValid( Tile ) then
			Tile:OnPreviewTextureFailed( Err )
		end
		return
	end

	self.Logger:Debug( "Loaded preview image for %s as %s.", MapName, TextureName )

	if SGUI.IsValid( Tile ) then
		Tile:SetPreviewTexture( TextureName )

		local Overlay = MapDataRepository.GetPreviewOverlay( MapName )
		Tile:SetPreviewOverlayTexture( Overlay )
	end
end

function MapVoteMenu:SetLoadModPreviews( LoadModPreviews )
	local WasLoading = self:GetLoadModPreviews()

	self.LoadModPreviews = not not LoadModPreviews

	if not WasLoading and LoadModPreviews then
		-- Load previews for any tile that's not already loaded it.
		local Maps = {}

		for i = 1, #self.MapTiles do
			local Tile = self.MapTiles[ i ]
			if Tile.ModID and Tile:GetPreviewTexture() == MapTile.UNKNOWN_MAP_PREVIEW_TEXTURE then
				Tile:SetPreviewTexture( nil )
				Maps[ #Maps + 1 ] = {
					ModID = Tile.ModID,
					MapName = Tile.MapName
				}
			end
		end

		if #Maps > 0 then
			MapDataRepository.GetPreviewImages( Maps, function( MapName, TextureName, Err )
				OnPreviewImageLoaded( self, MapName, TextureName, Err )
			end )
		end
	elseif WasLoading and not LoadModPreviews then
		for i = 1, #self.MapTiles do
			local Tile = self.MapTiles[ i ]
			if Tile.ModID and Tile:GetPreviewTexture() ~= MapTile.UNKNOWN_MAP_PREVIEW_TEXTURE then
				TextureLoader.Free( Tile:GetPreviewTexture() )
				Tile:SetPreviewTexture( MapTile.UNKNOWN_MAP_PREVIEW_TEXTURE )
			end
		end
	end

	if self.LoadModPreviews ~= WasLoading then
		self:OnPropertyChanged( "LoadModPreviews", self.LoadModPreviews )
	end
end

function MapVoteMenu:SetMaps( Maps )
	local LoadModPreviews = self:GetLoadModPreviews()
	for i = 1, #Maps do
		local Entry = Maps[ i ]
		local Tile = SGUI:CreateFromDefinition( MapTile, self.Elements.MapTileGrid )
		Tile:SetDebugName( "MapVoteTile:%s/%s", Entry.ModID, Entry.MapName )
		Tile:SetMapVoteMenu( self )
		Tile:SetSkin( Skin )
		Tile:SetMap( Entry.ModID, Entry.MapName, Entry.PreviewName )

		if Entry.MapName == self:GetCurrentMap() then
			Tile:SetMapNameText(
				Locale:GetInterpolatedPhrase( "mapvote", "MAP_VOTE_MENU_EXTEND_MAP", {
					MapName = Entry.NiceName
				} )
			)
		else
			Tile:SetMapNameText( Entry.NiceName )
		end

		Tile:SetSelected( Entry.IsSelected )
		Tile:SetNumVotes( Entry.NumVotes )
		Tile:SetInheritsParentAlpha( true )
		Tile:SetTeamVariation( self:GetTeamVariation() )

		if #Maps > 9 then
			Tile:SetStyleName( "SmallerFonts" )
		end

		if not LoadModPreviews and Entry.ModID then
			Tile:OnPreviewTextureFailed( "Mod previews are disabled." )
		end

		self.MapTiles[ i ] = Tile
		self.MapTiles[ Entry.MapName ] = Tile
	end

	local MapsToLoad = Maps
	if not LoadModPreviews then
		MapsToLoad = Shine.Stream.Of( Maps ):Filter( function( Map )
			return not Map.ModID
		end ):AsTable()
	end

	if #MapsToLoad > 0 then
		-- Setup each tile with their preview image upfront, as they'll be visible immediately.
		MapDataRepository.GetPreviewImages( MapsToLoad, function( MapName, TextureName, Err )
			OnPreviewImageLoaded( self, MapName, TextureName, Err )
		end )
	end

	self:RefreshMapVoteTileWinners()
	self:InvalidateLayout( true )
end

function MapVoteMenu:SetupTileGrid()
	local Container = self.Elements.MapTileGridLayout
	local Padding = Container:GetComputedPadding()

	local Size = Vector( Container:GetSize() )
	Size.x = Size.x - Units.Spacing.GetWidth( Padding )
	Size.y = Size.y - Units.Spacing.GetHeight( Padding )

	local UniformGridSize = Ceil( Sqrt( #self.MapTiles ) )

	-- Bias the grid to being wider than it is tall, as basically every screen has more width than height.
	local NumRows = Max( 1, UniformGridSize - 1 )
	local NumColumns = Ceil( #self.MapTiles / NumRows )
	local Margin = Units.GUIScaled( 8 ):GetValue()

	local TileSize = Min(
		Floor( Size.y / NumRows - Margin * ( NumRows - 1 ) ),
		Floor( Size.x / NumColumns - Margin * ( NumColumns - 1 ) )
	)

	Container:Clear()

	local TileIndex = 1
	for i = 1, NumRows do
		local Row = SGUI.Layout:CreateLayout( "Horizontal", {
			Margin = i > 1 and Units.Spacing( 0, Margin, 0, 0 ) or nil,
			AutoSize = Units.UnitVector(
				NumColumns * TileSize + Margin * ( NumColumns - 1 ),
				TileSize
			),
			Fill = false,
			Alignment = SGUI.LayoutAlignment.CENTRE,
			CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE
		} )
		Container:AddElement( Row )

		for j = 1, NumColumns do
			local Tile = self.MapTiles[ TileIndex ]
			if not Tile then break end

			Tile:SetSize( Vector2( TileSize, TileSize ) )
			if j > 1 then
				Tile:SetMargin( Units.Spacing( Margin, 0, 0, 0 ) )
			end
			Row:AddElement( Tile )

			TileIndex = TileIndex + 1
		end
	end
end

function MapVoteMenu:Think( DeltaTime )
	Controls.Panel.Think( self, DeltaTime )

	local TimeLeft = Ceil( self.EndTime - SharedTime() )
	self.Elements.CountdownLabel:SetText( StringDigitalTime( TimeLeft ) )
	if TimeLeft <= 10 and self.Elements.CountdownLabel:GetStyleName() ~= "CountdownTimeRunningOut" then
		self.Elements.CountdownLabel:SetStyleName( "CountdownTimeRunningOut" )
	end
end

function MapVoteMenu:RefreshMapVoteTileWinners()
	local Max = 0
	local NumAtMax = 0
	for i = 1, #self.MapTiles do
		local Tile = self.MapTiles[ i ]
		local VotesForTile = Tile:GetNumVotes()
		if VotesForTile > Max then
			Max = VotesForTile
			NumAtMax = 1
		elseif VotesForTile == Max then
			NumAtMax = NumAtMax + 1
		end
	end

	for i = 1, #self.MapTiles do
		local Tile = self.MapTiles[ i ]
		local VotesForTile = Tile:GetNumVotes()
		if VotesForTile == Max and Max > 0 then
			Tile:SetWinnerType( MapTile.WinnerTypeName[ NumAtMax > 1 and "TIED_WINNER" or "WINNER" ] )
		else
			Tile:SetWinnerType( nil )
		end
	end
end

function MapVoteMenu:OnMapVoteCountChanged( MapName, NumVotes )
	local Tile = self.MapTiles[ MapName ]
	if not SGUI.IsValid( Tile ) then return end

	Tile:SetNumVotes( NumVotes )

	self:RefreshMapVoteTileWinners()
end

function MapVoteMenu:OnMapSelected( MapName )

end

function MapVoteMenu:OnMapDeselected( MapName )

end

function MapVoteMenu:GetNumSelectedMaps()
	local Count = 0
	for i = 1, #self.MapTiles do
		local Tile = self.MapTiles[ i ]
		if SGUI.IsValid( Tile ) and Tile:GetSelected() then
			Count = Count + 1
		end
	end
	return Count
end

function MapVoteMenu:DeselectMap( MapName )
	local Tile = self.MapTiles[ MapName ]
	if SGUI.IsValid( Tile ) then
		Tile:SetSelected( false )
	end
end

function MapVoteMenu:ForceSelectedMap( MapName )
	if self:GetMultiSelect() then
		local Tile = self.MapTiles[ MapName ]
		if SGUI.IsValid( Tile ) and not Tile:GetSelected() then
			Tile:SetSelected( true )
			return true
		end

		return false
	end

	if MapName == self.SelectedMap then return false end

	self.SelectedMap = MapName

	local PreviouslySelected = self.SelectedMapTile
	if SGUI.IsValid( PreviouslySelected ) then
		PreviouslySelected:SetSelected( false )
	end

	local Tile = self.MapTiles[ MapName ]
	if SGUI.IsValid( Tile ) then
		Tile:SetSelected( true )
		self.SelectedMapTile = Tile
	end

	return true
end

function MapVoteMenu:SetSelectedMap( MapName )
	if self:GetMultiSelect() and self:GetNumSelectedMaps() >= self:GetMaxVoteChoices() then
		SGUI.NotificationManager.AddNotification(
			Shine.NotificationType.ERROR,
			Locale:GetInterpolatedPhrase( "mapvote", "VOTE_FAIL_CHOICE_LIMIT_REACHED", {
				MaxMapChoices = self:GetMaxVoteChoices()
			} ),
			3
		)
		return
	end

	if not self:ForceSelectedMap( MapName ) then return end

	self:OnMapSelected( MapName )

	if not self:GetMultiSelect() then
		self:OnPropertyChanged( "SelectedMap", MapName )
		if self:GetCloseOnClick() then
			self:Close()
		end
	end
end

function MapVoteMenu:ResetSelectedMap( MapName )
	if not self:GetMultiSelect() then return end

	self:DeselectMap( MapName )
	self:OnMapDeselected( MapName )
end

function MapVoteMenu:Cleanup()
	-- Free any rendered textures.
	for i = 1, #self.MapTiles do
		local Tile = self.MapTiles[ i ]
		TextureLoader.Free( Tile:GetPreviewTexture() )

		local OverviewTexture = Tile:GetOverviewTexture()
		if OverviewTexture then
			TextureLoader.Free( OverviewTexture )
		end
	end

	self.BaseClass.Cleanup( self )
end

return MapVoteMenu
