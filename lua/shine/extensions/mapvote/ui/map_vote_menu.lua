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
			Shader = "shaders/shine/gui_none.surface_shader"
		},
		ShowOverviewButton = {
			TextColour = Colour( 1, 1, 1, 1 ),
			TextInheritsParentAlpha = true,
			InheritsParentAlpha = true,
			Shader = "shaders/shine/gui_none.surface_shader"
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
			InheritsParentAlpha = true
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
			Colour = Colour( 1, 1, 1, 0 )
		}
	},
	MapTile = {
		Default = {
			TextColour = Colour( 1, 1, 1, 1 / MapTileHeaderAlpha ),
			IconColour = Colour( 0, 1, 0, 1 ),
			InactiveCol = Colour( 0, 0, 0, 1 ),
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
			Shader = "shaders/shine/gui_none.surface_shader"
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
	Column = HeaderVariations
}

local MapVoteMenu = SGUI:DefineControl( "MapVoteMenu", "Panel" )

SGUI.AddProperty( MapVoteMenu, "EndTime" )

function MapVoteMenu:Initialise()
	Controls.Panel.Initialise( self )
	self:SetSkin( Skin )

	self.Background:SetShader( "shaders/shine/gui_none.surface_shader" )
	self.MapTiles = {}

	local TeamVariation = self:GetTeamVariation()
	local SmallPadding = Units.GUIScaled( 8 )

	self.Elements = SGUI:BuildTree( self, {
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
						AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() + Units.GUIScaled( 16 ) ),
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
						}
					}
				},
				{
					ID = "InformationBox",
					Class = "Row",
					Props = {
						AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() + SmallPadding ),
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
					Type = "Layout",
					ID = "MapTileGridLayout",
					Class = "Vertical",
					Props = {
						Margin = Units.Spacing( 0, SmallPadding, 0, 0 )
					}
				}
			}
		}
	} )

	self.Elements.MapTileGridLayout:AddPropertyChangeListener( "Size", function( Size )
		self:SetupTileGrid()
	end )

	self.TitleBarHeight = Units.GUIScaled( 32 ):GetValue()
	self:AddCloseButton( self )
end

function MapVoteMenu:GetTeamVariation()
	local Player = Client.GetLocalPlayer()
	return Player and Player:isa( "Alien" ) and "Alien" or "Marine"
end

function MapVoteMenu:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end

	if Key == InputKey.Escape and Down then
		self:Close()
		return true
	end

	return Controls.Panel.PlayerKeyPress( self, Key, Down )
end

function MapVoteMenu:FadeIn()
	self:SetIsVisible( true )
	self:AlphaTo( nil, 0, 1, 0, 0.3 )

	local TeamVariation = self:GetTeamVariation()
	self.Elements.TitleBox:SetStyleName( TeamVariation )
	self.Elements.InformationBox:SetStyleName( TeamVariation )

	for i = 1, #self.MapTiles do
		self.MapTiles[ i ]:SetTeamVariation( TeamVariation )
	end
end

function MapVoteMenu:FadeOut( Callback )
	self:AlphaTo( nil, nil, 0, 0, 0.3, function()
		self:SetIsVisible( false )
		self:OnClose()
		if Callback then
			-- Call after Think exits to avoid destroying GUIItems that are in use.
			SGUI:AddPostEventAction( Callback )
		end
	end )
end

function MapVoteMenu:OnClose()

end

function MapVoteMenu:Close( Callback )
	if not self:GetIsVisible() then
		if Callback then
			Callback()
		end
		return
	end

	self:FadeOut( Callback )
	SGUI:EnableMouse( false )
end

function MapVoteMenu:SetCurrentMapName( MapName )
	self.Elements.CurrentMapLabel:SetText(
		Locale:GetInterpolatedPhrase( "mapvote", "MAP_VOTE_MENU_CURRENT_MAP", { MapName = MapName } )
	)
end

function MapVoteMenu:SetMaps( Maps )
	for i = 1, #Maps do
		local Entry = Maps[ i ]
		local Tile = SGUI:CreateFromDefinition( MapTile, self )
		Tile:SetSkin( Skin )
		Tile:SetMap( Entry.ModID, Entry.MapName )
		Tile:SetText( Entry.NiceName )
		Tile:SetSelected( Entry.IsSelected )
		Tile:SetNumVotes( Entry.NumVotes )
		Tile:SetInheritsParentAlpha( true )
		Tile:SetTeamVariation( self:GetTeamVariation() )

		self.MapTiles[ i ] = Tile
		self.MapTiles[ Entry.MapName ] = Tile
	end

	-- Setup each tile with their preview image upfront, as they'll be visible immediately.
	MapDataRepository.GetPreviewImages( Maps, function( MapName, TextureName, Err )
		if not SGUI.IsValid( self ) then
			if not Err then
				TextureLoader.Free( TextureName )
			end
			return
		end

		if Err then
			LuaPrint( "Failed to load preview image for", MapName, Err )
			Tile:OnPreviewTextureFailed( Err )
			return
		end

		LuaPrint( "Loaded preview image for", MapName, "as", TextureName )

		local Tile = self.MapTiles[ MapName ]
		if SGUI.IsValid( Tile ) then
			Tile:SetPreviewTexture( TextureName )
		end
	end )

	self:InvalidateLayout( true )
end

function MapVoteMenu:SetupTileGrid()
	local Container = self.Elements.MapTileGridLayout
	local Size = Container:GetSize()

	local UniformGridSize = Ceil( Sqrt( #self.MapTiles ) )

	-- Bias the grid to being wider than it is tall, as basically every screen has more width than height.
	local NumRows = Max( 1, UniformGridSize - 1 )
	local NumColumns = Ceil( #self.MapTiles / NumRows )
	local Margin = 0--Units.HighResScaled( 8 ):GetValue()

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

function MapVoteMenu:OnMapVoteCountChanged( MapName, NumVotes )
	local Tile = self.MapTiles[ MapName ]
	if not SGUI.IsValid( Tile ) then return end

	Tile:SetNumVotes( NumVotes )
end

function MapVoteMenu:SetSelectedMap( MapName )
	if MapName == self.SelectedMap then return end

	self.SelectedMap = MapName
	self:OnPropertyChanged( "SelectedMap", MapName )

	local PreviouslySelected = self.SelectedMapTile
	if SGUI.IsValid( PreviouslySelected ) then
		PreviouslySelected:SetSelected( false )
	end

	local Tile = self.MapTiles[ MapName ]
	if not SGUI.IsValid( Tile ) then return end

	Tile:SetSelected( true )
	self.SelectedMapTile = Tile
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
