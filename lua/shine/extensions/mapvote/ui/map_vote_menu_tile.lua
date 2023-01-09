--[[
	A simple tile button used to display a map, its number of votes, and whether
	it has been chosen.

	On hover, buttons to toggle display of the overview of the map and to open the map's mod workshop page (if a mod)
	are displayed.
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

SGUI.AddBoundProperty( MapTile, "MapNameText", "MapNameLabel:SetText" )
SGUI.AddBoundProperty( MapTile, "MapNameAutoFont", "MapNameLabel:SetAutoFont" )
SGUI.AddBoundProperty( MapTile, "TextColour", {
	"Label:SetColour", "MapNameLabel:SetColour", "VoteCounterLabel:SetColour"
} )
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
				AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, Units.Percentage.ONE_HUNDRED )
			},
			Children = {
				{
					ID = "PreviewImage",
					Class = "Image",
					Props = {
						Fill = true,
						IsVisible = false,
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
							Listener = function( Image, Texture )
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
								self.PreviewImage:ApplyTransition( {
									Type = "AlphaMultiplier",
									StartValue = 0,
									EndValue = 1,
									Duration = 0.3
								} )
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
								AutoSize = Units.UnitVector( Units.Percentage.TWENTY_FIVE, 0 ),
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
			ID = "HeaderRow",
			Class = "Row",
			Props = {
				AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ),
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
						AutoSize = Units.UnitVector( Units.Auto.INSTANCE, Units.Auto.INSTANCE ),
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
						AutoSize = Units.UnitVector( Units.Auto.INSTANCE, Units.Auto.INSTANCE ),
						DoClick = function()
							self:ToggleOverviewImage()
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
			ID = "FooterRow",
			Class = "Row",
			Props = {
				AutoSize = Units.UnitVector( Units.Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ),
				PositionType = SGUI.PositionType.ABSOLUTE,
				TopOffset = Units.Percentage.ONE_HUNDRED - Units.Auto.INSTANCE,
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
					Units.Min( Units.Auto.INSTANCE, Units.Percentage.ONE_HUNDRED - Units.Auto( Elements.ShowOverviewButton ) * 2 ),
					Units.Auto.INSTANCE
				)
			)
		end
	} ), self )

	Binder():FromElement( self, "Selected" )
		:ToElement( self, "Icon", {
			Transformer = function( Selected )
				if Selected then
					return SGUI.Icons.Ionicons.Checkmark,
						SGUI.FontManager.GetFont( SGUI.FontFamilies.Ionicons, 64 )
				end
				return nil
			end
		} ):BindProperty()
end

-- This is used externally to render a map preview without any interactive elements.
function MapTile:EnableDisplayMode()
	self:SetHighlightOnMouseOver( false )
	self:SetHighlighted( true, true )
	self:SetEnabled( false )
	self.InheritsParentAlpha = true
	self:SetPropagateAlphaInheritance( true )

	self:AddStylingState( "Display" )

	self.DisplayMode = true

	if SGUI.IsValid( self.HeaderRow ) then
		self.HeaderRow:Destroy()
		self.HeaderRow = nil
	end

	if SGUI.IsValid( self.FooterRow ) then
		self.FooterRow:Destroy()
		self.FooterRow = nil
	end

	self.DoClick = function() end
end

function MapTile:SetHighlighted( Highlighted, SkipAnim )
	self.Highlighted = Highlighted
	self:OnPropertyChanged( "Highlighted", Highlighted )

	if not SGUI.IsValid( self.PreviewImage ) then return end

	local Colour = Highlighted and self.PreviewImage.ActiveCol or self.PreviewImage.InactiveCol
	if SkipAnim then
		self.PreviewImage:SetColour( Colour )
		return
	end

	self.PreviewImage:ApplyTransition( {
		Type = "Fade",
		EndValue = Colour,
		Duration = 0.1
	} )
end

function MapTile:SetPreviewOverlayTexture( Overlay )
	if not Overlay then
		if SGUI.IsValid( self.PreviewImageOverlay ) then
			self.PreviewImageOverlay:Destroy()
			self.PreviewImageOverlay = nil
		end
		return
	end

	local OverlayElement = self.PreviewImageOverlay
	if not SGUI.IsValid( OverlayElement ) then
		OverlayElement = SGUI:Create( "Image", self.PreviewImage )
		OverlayElement:SetPositionType( SGUI.PositionType.ABSOLUTE )
		OverlayElement:SetFill( true )
		self.PreviewImageOverlay = OverlayElement
	end

	OverlayElement:SetTexture( Overlay )
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
							Colour = Colour( 0, 0, 0, 0.5 ),
							Fill = true
						},
						Children = {
							{
								ID = "OverviewImageLoadingIndicator",
								Class = "ProgressWheel",
								Props = {
									Fraction = 0.75,
									Alignment = SGUI.LayoutAlignment.CENTRE,
									CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
									AutoSize = Units.UnitVector( Units.Percentage.TWENTY_FIVE, 0 ),
									AspectRatio = 1,
									StyleName = self:GetTeamVariation()
								}
							},
							{
								ID = "OverviewImage",
								Class = "Image",
								Props = {
									IsVisible = false,
									Colour = Colour( 1, 1, 1, 1 ),
									Texture = self.OverviewTexture,
									Alignment = SGUI.LayoutAlignment.CENTRE,
									CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
									AspectRatio = 1,
									AutoSize = Units.UnitVector(
										Units.Percentage[ self.DisplayMode and "ONE_HUNDRED" or "SEVENTY_FIVE" ],
										0
									)
								}
							}
						}
					}
				}
			}
		} ), self )
		self.PreviewImage:InvalidateLayout( true )
		self.OverviewImageContainer:ApplyTransition( {
			Type = "AlphaMultiplier",
			EndValue = 1,
			Duration = 0.3
		} )
	end

	if self.OverviewTexture then
		if SGUI.IsValid( self.OverviewImageLoadingIndicator ) then
			self.OverviewImageLoadingIndicator:Destroy()
			self.OverviewImageLoadingIndicator = nil
		end

		self.OverviewImage:SetTexture( self.OverviewTexture )
		self.OverviewImage:SetIsVisible( true )
		self.OverviewImage:ApplyTransition( {
			Type = "AlphaMultiplier",
			EndValue = 1,
			Duration = 0.3
		} )
		return
	end

	local MapNameToLoad = self.PreviewName or self.MapName
	MapDataRepository.GetOverviewImage( self.ModID, MapNameToLoad, function( MapName, TextureName, Err )
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
		self.OverviewImageContainer:ApplyTransition( {
			Type = "AlphaMultiplier",
			EndValue = 0,
			Duration = 0.3,
			Callback = function()
				self.PreviewImage:SetLayout( nil )
				self.OverviewImage:StopAlpha()

				self.OverviewImageContainer:Destroy()
				self.OverviewImageContainer = nil
				self.OverviewImage = nil
			end
		} )
	end
end

function MapTile:ToggleOverviewImage()
	if SGUI.IsValid( self.OverviewImageContainer ) then
		self:HideOverviewImage()
		return false
	end

	self:ShowOverviewImage()

	return true
end

function MapTile:DoClick()
	if self:GetSelected() then
		self.MapVoteMenu:ResetSelectedMap( self.MapName )
	else
		self.MapVoteMenu:SetSelectedMap( self.MapName )
	end

	return true
end

function MapTile:SetMap( ModID, MapName, PreviewName )
	self.ModID = ModID
	self.MapName = MapName
	self.PreviewName = PreviewName
end

function MapTile:OnPreviewTextureFailed( Err )
	self:SetPreviewTexture( self.UNKNOWN_MAP_PREVIEW_TEXTURE )
end

return MapTile
