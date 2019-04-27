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

local Skin = {
	Button = {
		CloseButton = {
			InactiveCol = Colour( 1, 1, 1, 0 ),
			ActiveCol = Colour( 1, 1, 1, 0 ),
			TextColour = Colour( 1, 1, 1, 1 ),
			TextInheritsParentAlpha = false
		}
	},
	Label = {
		Default = {
			Colour = Colour( 1, 1, 1, 1 )
		}
	},
	MapVoteMenu = {
		Default = {
			Colour = Colour( 1, 1, 1, 0 )
		}
	},
	MapTile = {
		Default = {
			TextColour = Colour( 1, 1, 1, 1 ),
			IconColour = Colour( 0, 1, 0, 1 ),
			InactiveCol = Colour( 0, 0, 0, 0 ),
			TextInheritsParentAlpha = false,
			MapNameAutoFont = {
				Family = "kAgencyFB",
				Size = Units.HighResScaled( 41 )
			},
			VoteCounterAutoFont = {
				Family = "kAgencyFB",
				Size = Units.HighResScaled( 41 )
			},
			IconShadow = {
				Colour = Colour( 0, 0, 0, 0.75 )
			}
		}
	},
	Row = {
		Header = {
			Colour = Colour( 1, 0.75, 0, 0.25 )
		},
		MapTileHeader = {
			Colour = Colour( 0, 0, 0, 0.5 )
		}
	},
	ShadowLabel = {
		Default = {
			Shadow = {
				Colour = Colour( 0, 0, 0, 0.75 )
			}
		}
	},
	Column = {
		Header = {
			Colour = Colour( 1, 0.75, 0, 0.25 )
		}
	}
}

local MapVoteMenu = SGUI:DefineControl( "MapVoteMenu", "Panel" )

SGUI.AddProperty( MapVoteMenu, "EndTime" )

function MapVoteMenu:Initialise()
	Controls.Panel.Initialise( self )
	self:SetSkin( Skin )

	self.TitleBarHeight = Units.HighResScaled( 32 ):GetValue()
	self:AddCloseButton( self )
	-- TODO: Propagate skins down to children automatically.
	self.CloseButton:SetSkin( Skin )

	self.MapTiles = {}

	local SmallPadding = Units.HighResScaled( 8 )

	self.Elements = SGUI:BuildTree( self, {
		GlobalProps = {
			Skin = Skin
		},
		{
			Type = "Layout",
			Class = "Vertical",
			Children = {
				{
					Class = "Column",
					Props = {
						AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() + Units.HighResScaled( 16 ) ),
						StyleName = "Header"
					},
					Children = {
						{
							Class = "ShadowLabel",
							Props = {
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoFont = {
									Family = SGUI.FontFamilies.MicrogrammaDBolExt,
									Size = Units.HighResScaled( 96 )
								},
								Text = Locale:GetPhrase( "mapvote", "MAP_VOTE_MENU_TITLE" )
							}
						}
					}
				},
				{
					Class = "Row",
					Props = {
						AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() + SmallPadding ),
						Margin = Units.Spacing( 0, SmallPadding, 0, 0 ),
						Padding = Units.Spacing( SmallPadding, 0, SmallPadding, 0 ),
						StyleName = "Header"
					},
					Children = {
						{
							ID = "CountdownLabel",
							Class = "ShadowLabel",
							Props = {
								Alignment = SGUI.LayoutAlignment.MAX,
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoFont = {
									Family = SGUI.FontFamilies.MicrogrammaDBolExt,
									Size = Units.HighResScaled( 29 )
								}
							}
						},
						{
							ID = "CurrentMapLabel",
							Class = "ShadowLabel",
							Props = {
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoFont = {
									Family = SGUI.FontFamilies.MicrogrammaDBolExt,
									Size = Units.HighResScaled( 29 )
								},
								Text = Shared.GetMapName()
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
end

function MapVoteMenu:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end

	if Key == InputKey.Escape then
		self:Close()
		return true
	end

	return Controls.Panel.PlayerKeyPress( self, Key, Down )
end

function MapVoteMenu:OnClose()

end

function MapVoteMenu:Close()
	if not self:GetIsVisible() then return end

	-- TODO: Add a nicer fade out animation when AnimateUI == true.
	self:SetIsVisible( false )
	SGUI:EnableMouse( false )
end

function MapVoteMenu:SetCurrentMapName( MapName )
	self.Elements.CurrentMapLabel:SetText( MapName )
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
		Tile:SetFill( true )

		self.MapTiles[ i ] = Tile
		self.MapTiles[ Entry.MapName ] = Tile
	end

	-- Setup each tile with their preview image upfront, as they'll be visible immediately.
	MapDataRepository.GetPreviewImages( Maps, function( MapName, TextureName, Err )
		if Err then
			LuaPrint( "Failed to load preview image for", MapName, Err )
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
	local Margin = Units.HighResScaled( 8 ):GetValue()

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

	local TimeLeft = self.EndTime - SharedTime()
	self.Elements.CountdownLabel:SetText( StringDigitalTime( TimeLeft ) )
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
