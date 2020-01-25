--[[
	A simple tile button used to display a map, its number of votes, and whether
	it has been chosen.

	On hover, the overview of the map is loaded and displayed.
]]

local Pi = math.pi
local StringFormat = string.format
local StringStartsWith = string.StartsWith
local TableShallowMerge = table.ShallowMerge

local Locale = Shine.Locale
local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local Binder = require "shine/lib/gui/binding/binder"
local MapDataRepository = require "shine/extensions/mapvote/map_data_repository"
local TextureLoader = require "shine/lib/gui/texture_loader"

local MapTile = SGUI:DefineControl( "MapTile", "Button" )

SGUI.AddProperty( MapTile, "MapVoteMenu" )
SGUI.AddProperty( MapTile, "NumVotes", 0 )
SGUI.AddProperty( MapTile, "OverviewTexture" )
SGUI.AddProperty( MapTile, "PreviewTexture" )
SGUI.AddProperty( MapTile, "Selected", false )
SGUI.AddProperty( MapTile, "TeamVariation", "Marine" )
SGUI.AddProperty( MapTile, "WinnerType" )

SGUI.AddBoundProperty( MapTile, "Text", "MapNameLabel:SetText" )
SGUI.AddBoundProperty( MapTile, "TextColour", { "MapNameLabel:SetColour", "VoteCounterLabel:SetColour" } )
SGUI.AddBoundProperty( MapTile, "MapNameAutoFont", "MapNameLabel:SetAutoFont" )
SGUI.AddBoundProperty( MapTile, "VoteCounterAutoFont", "VoteCounterLabel:SetAutoFont" )

MapTile.WinnerTypeName = table.AsEnum{
	"WINNER", "TIED_WINNER"
}

MapTile.UNKNOWN_MAP_PREVIEW_TEXTURE = "ui/shine/unknown_map.tga"

function MapTile:Initialise()
	Controls.Button.Initialise( self )

	self:SetHorizontal( false )
	self.Highlighted = false

	TableShallowMerge( SGUI:BuildTree( {
		Parent = self,
		{
			Type = "Layout",
			Class = "Vertical",
			Props = {
				Fill = false,
				AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Percentage( 100 ) )
			},
			Children = {
				{
					ID = "PreviewImage",
					Class = "Image",
					Props = {
						Fill = true,
						IsVisible = false,
						InheritsParentAlpha = true,
						StyleName = "PreviewImage"
					},
					Bindings = {
						{
							From = {
								Element = self,
								Property = "PreviewTexture"
							},
							To = {
								{
									Property = "Texture"
								},
								{
									Property = "TextureCoordinates",
									Filter = function( Texture )
										-- Apply only to mounted loading screens textures (assumed vanilla map).
										return Texture ~= nil and StringStartsWith( Texture, "screens/" )
									end,
									Transformer = function( Texture )
										-- Magic numbers that seem to work well. Thankfully each loading screen seems to
										-- follow a standard template with the same position for the map name + minimap.
										return 185 / 1920, 185 / 1200, ( 185 + 875 ) / 1920, ( 185 + 875 ) / 1200
									end
								}
							}
						}
					},
					PropertyChangeListeners = {
						{
							Property = "Texture",
							Listener = function( Texture )
								if not Texture then
									if SGUI.IsValid( self.LoadingIndicatorContainer ) then
										self.LoadingIndicatorContainer:SetIsVisible( true )
										self.PreviewImage:SetIsVisible( false )
									end
									return
								end

								if SGUI.IsValid( self.LoadingIndicatorContainer ) then
									self.LoadingIndicatorContainer:SetIsVisible( false )
								end

								self.PreviewImage:SetIsVisible( true )

								if StringStartsWith( Texture, "screens/" ) then
									-- Image was already mounted (thus there was no delay), display immediately.
									return
								end

								-- Fade the image in after loading.
								self.PreviewImage:AlphaTo( nil, 0, 1, 0, 0.3 )
							end
						}
					}
				},
				{
					ID = "LoadingIndicatorContainer",
					Class = "Row",
					Props = {
						Fill = true,
						StyleName = "LoadingIndicatorContainer"
					},
					Children = {
						{
							ID = "LoadingIndicator",
							Class = "ProgressWheel",
							Props = {
								Alignment = SGUI.LayoutAlignment.CENTRE,
								CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
								AutoSize = Units.UnitVector( Units.Percentage( 25 ), 0 ),
								AspectRatio = 1,
								StyleName = self:GetTeamVariation()
							},
							Bindings = {
								{
									From = {
										Element = self,
										Property = "TeamVariation"
									},
									To = {
										Property = "StyleName"
									}
								}
							}
						}
					}
				}
			}
		},
		{
			Class = "Row",
			Props = {
				AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() ),
				Padding = Units.Spacing( Units.GUIScaled( 4 ), 0, Units.GUIScaled( 4 ), 0 ),
				PositionType = SGUI.PositionType.ABSOLUTE,
				Anchor = "TopLeft",
				StyleName = "MapTileHeader"
			},
			Children = {
				{
					ID = "ShowModButton",
					Class = "Button",
					Props = {
						Icon = SGUI.Icons.Ionicons.Wrench,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						StyleName = "ShowOverviewButton",
						AutoSize = Units.UnitVector( Units.Auto(), Units.Auto() ),
						IsVisible = false,
						DoClick = function()
							Client.ShowWebpage( StringFormat( "https://steamcommunity.com/sharedfiles/filedetails/?id=%s", self.ModID ) )
						end,
						Tooltip = Locale:GetPhrase( "mapvote", "SHOW_MOD_TOOLTIP" )
					},
					Bindings = {
						{
							From = {
								Element = self,
								Property = "Highlighted",
							},
							To = {
								Property = "IsVisible",
								Filter = function() return self.ModID ~= nil end
							}
						}
					}
				},
				{
					ID = "MapNameLabel",
					Class = "Label",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						AutoWrap = true,
						StyleName = "MapTileLabel"
					}
				},
				{
					ID = "ShowOverviewButton",
					Class = "Button",
					Props = {
						Icon = SGUI.Icons.Ionicons.Earth,
						Alignment = SGUI.LayoutAlignment.MAX,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						StyleName = "ShowOverviewButton",
						AutoSize = Units.UnitVector( Units.Auto(), Units.Auto() ),
						DoClick = function()
							if SGUI.IsValid( self.OverviewImageContainer ) then
								self:HideOverviewImage()
							else
								self:ShowOverviewImage()
							end
						end,
						Tooltip = Locale:GetPhrase( "mapvote", "TOGGLE_MAP_OVERVIEW_TOOLTIP" )
					},
					Bindings = {
						{
							From = {
								Element = self,
								Property = "Highlighted",
							},
							To = {
								Property = "IsVisible"
							}
						}
					}
				}
			}
		},
		{
			Class = "Row",
			Props = {
				AutoSize = Units.UnitVector( Units.Percentage( 100 ), Units.Auto() ),
				PositionType = SGUI.PositionType.ABSOLUTE,
				TopOffset = Units.Percentage( 100 ) - Units.Auto(),
				Anchor = "TopLeft",
				StyleName = "MapTileHeader"
			},
			Children = {
				{
					ID = "VoteCounterLabel",
					Class = "Label",
					Props = {
						Alignment = SGUI.LayoutAlignment.CENTRE,
						CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
						StyleName = "MapTileLabel"
					},
					Bindings = {
						{
							From = {
								Element = self,
								Property = "NumVotes"
							},
							To = {
								Property = "Text",
								Transformer = function( NumVotes )
									return Locale:GetInterpolatedPhrase( "mapvote", "VOTE_COUNTER", {
										NumVotes = NumVotes
									} )
								end
							}
						},
						{
							From = {
								Element = self,
								Property = "WinnerType"
							},
							To = {
								Property = "StyleName",
								Transformer = function( WinnerType )
									if WinnerType == self.WinnerTypeName.WINNER then
										return "MapTileVoteCountWinner"
									end

									if WinnerType == self.WinnerTypeName.TIED_WINNER then
										return "MapTileVoteCountTied"
									end

									return "MapTileLabel"
								end
							}
						}
					}
				}
			}
		},
		OnBuilt = function( Elements )
			Elements.MapNameLabel:SetAutoSize(
				Units.UnitVector(
					Units.Min( Units.Auto(), Units.Percentage( 100 ) - Units.Auto( Elements.ShowOverviewButton ) * 2 ),
					Units.Auto()
				)
			)
		end
	} ), self )

	Binder():FromElement( self, "Selected" )
		:ToElement( self, "Icon", {
			Transformer = function( Selected )
				if Selected then
					return SGUI.Icons.Ionicons.Checkmark,
						SGUI.FontManager.GetHighResFont( SGUI.FontFamilies.Ionicons, 64 )
				end
				return nil
			end
		} ):BindProperty()
end

function MapTile:SetHighlighted( Highlighted, SkipAnim )
	self.Highlighted = Highlighted
	self:OnPropertyChanged( "Highlighted", Highlighted )

	local Colour = Highlighted and self.PreviewImage.ActiveCol or self.PreviewImage.InactiveCol
	if SkipAnim then
		self.PreviewImage:SetColour( Colour )
		return
	end

	self.PreviewImage:FadeTo( self.PreviewImage.Background, nil, Colour, 0, 0.1 )
end

function MapTile:ShowOverviewImage()
	if not SGUI.IsValid( self.OverviewImageContainer ) then
		TableShallowMerge( SGUI:BuildTree( {
			Parent = self.PreviewImage,
			{
				Type = "Layout",
				Class = "Vertical",
				Children = {
					{
						ID = "OverviewImageContainer",
						Class = "Column",
						Props = {
							Colour = Colour( 0, 0, 0, 0 ),
							Fill = true,
							InheritsParentAlpha = true
						},
						Children = {
							{
								ID = "OverviewImageLoadingIndicator",
								Class = "ProgressWheel",
								Props = {
									Fraction = 0.75,
									Alignment = SGUI.LayoutAlignment.CENTRE,
									CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
									AutoSize = Units.UnitVector( Units.Percentage( 25 ), 0 ),
									AspectRatio = 1,
									StyleName = self:GetTeamVariation()
								}
							},
							{
								ID = "OverviewImage",
								Class = "Image",
								Props = {
									IsVisible = false,
									Colour = Colour( 1, 1, 1, 0 ),
									Texture = self.OverviewTexture,
									Alignment = SGUI.LayoutAlignment.CENTRE,
									CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
									AspectRatio = 1,
									AutoSize = Units.UnitVector( Units.Percentage( 75 ), 0 ),
									InheritsParentAlpha = true
								}
							}
						}
					}
				}
			}
		} ), self )
		self.PreviewImage:InvalidateLayout( true )
		self.OverviewImageContainer:AlphaTo( nil, nil, 0.5, 0, 0.3 )
	end

	if self.OverviewTexture then
		if SGUI.IsValid( self.OverviewImageLoadingIndicator ) then
			self.OverviewImageLoadingIndicator:Destroy()
			self.OverviewImageLoadingIndicator = nil
		end

		self.OverviewImage:SetTexture( self.OverviewTexture )
		self.OverviewImage:SetIsVisible( true )
		self.OverviewImage:AlphaTo( nil, nil, 2, 0, 0.3 )
		return
	end

	MapDataRepository.GetOverviewImage( self.ModID, self.MapName, function( MapName, TextureName, Err )
		if not SGUI.IsValid( self ) then
			if not Err then
				TextureLoader.Free( TextureName )
			end
			return
		end

		if Err then
			TextureName = "ui/shine/unknown_map.tga"
		end

		self:SetOverviewTexture( TextureName )
		self:ShowOverviewImage()
	end )
end

function MapTile:HideOverviewImage()
	if SGUI.IsValid( self.OverviewImageContainer ) then
		self.OverviewImageContainer:AlphaTo( nil, nil, 0, 0, 0.3, function()
			self.PreviewImage:SetLayout( nil )
			self.OverviewImage:StopAlpha()

			self.OverviewImageContainer:Destroy()
			self.OverviewImageContainer = nil
			self.OverviewImage = nil
		end )
	end
end

function MapTile:DoClick()
	self.MapVoteMenu:SetSelectedMap( self.MapName )
	return true
end

function MapTile:SetMap( ModID, MapName )
	self.ModID = ModID
	self.MapName = MapName
end

function MapTile:OnPreviewTextureFailed( Err )
	self:SetPreviewTexture( self.UNKNOWN_MAP_PREVIEW_TEXTURE )
end

return MapTile
