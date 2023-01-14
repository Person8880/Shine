--[[
	Base commands client.
]]

local Plugin = ...

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"
Plugin.DefaultConfig = {
	DisableLocalAllTalk = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

local Shine = Shine
local Hook = Shine.Hook
local SGUI = Shine.GUI

local StringFind = string.find
local StringMatch = string.match
local StringFormat = string.format
local StringTimeToString = string.TimeToString
local TableEmpty = table.Empty
local TableShallowMerge = table.ShallowMerge
local TableSort = table.sort

Shine.Hook.Add( "PostLoadScript:lua/Voting.lua", "SetupCustomVote", function( Reload )
	RegisterVoteType( "ShineCustomVote", {
		VoteQuestion = "string (128)"
	} )

	AddVoteSetupCallback( function( VoteMenu )
		AddVoteStartListener( "ShineCustomVote", function( Data )
			return Data.VoteQuestion
		end )
	end )
end )

local TeamChangeMessageKeys = {
	[ 0 ] = "CHANGE_TEAM_READY_ROOM",
	"CHANGE_TEAM_MARINE",
	"CHANGE_TEAM_ALIEN",
	"CHANGE_TEAM_SPECTATOR"
}

do
	local RichTextFormat = require "shine/lib/gui/richtext/format"

	local function GetColourForName( Values )
		return RichTextFormat.GetColourForPlayer( Values.TargetName )
	end

	local TargetMessageOptions = {
		Colours = {
			TargetName = GetColourForName
		}
	}

	local RichTextMessageOptions = {
		CLIENT_KICKED = TargetMessageOptions,
		CLIENT_KICKED_REASON = {
			Colours = {
				TargetName = GetColourForName,
				Reason = RichTextFormat.Colours.LightRed
			}
		},
		FRIENDLY_FIRE_SCALE = {
			Colours = {
				Scale = RichTextFormat.Colours.LightBlue
			}
		},
		RANDOM_TEAM = {
			Colours = {
				TargetCount = RichTextFormat.Colours.LightBlue
			}
		},
		PLAYER_GAGGED = {
			Colours = {
				TargetName = GetColourForName,
				Duration = RichTextFormat.Colours.LightBlue
			}
		}
	}

	for i = 0, 3 do
		RichTextMessageOptions[ TeamChangeMessageKeys[ i ] ] = {
			Colours = {
				TargetCount = RichTextFormat.Colours.LightBlue
			}
		}
	end

	local ToggleMessageOptions = {
		Colours = {
			Enabled = function( Values )
				return Values.Enabled and Colour( 0, 1, 0 ) or Colour( 1, 0, 0 )
			end
		}
	}

	for i = 1, #Plugin.ToggleNotificationKeys do
		RichTextMessageOptions[ Plugin.ToggleNotificationKeys[ i ] ] = ToggleMessageOptions
	end

	for i = 1, #Plugin.TargetNotificationKeys do
		RichTextMessageOptions[ Plugin.TargetNotificationKeys[ i ] ] = TargetMessageOptions
	end

	Plugin.RichTextMessageOptions = RichTextMessageOptions
end

function Plugin:Initialise()
	if self.dt.AllTalk or self.dt.AllTalkPreGame then
		self:UpdateAllTalk( self.dt.Gamestate )
	end

	self:SetupAdminMenuCommands()
	self:SetupClientConfig()

	self.Enabled = true

	return true
end

function Plugin:NetworkUpdate( Key, Old, New )
	if Key == "Gamestate" then
		if ( Old == kGameState.PreGame or Old == kGameState.WarmUp ) and New == kGameState.NotStarted then
			-- The game state changes back to NotStarted, then to Countdown to start. This is VERY annoying...
			self:SimpleTimer( 1, function()
				if self.dt.Gamestate == kGameState.NotStarted then
					self:UpdateAllTalk( self.dt.Gamestate )
				end
			end )

			return
		end

		self:UpdateAllTalk( New )
	elseif Key == "AllTalk" then
		if not New and not self.dt.AllTalkPreGame then
			self:RemoveAllTalkText()
		else
			self:UpdateAllTalk( self.dt.Gamestate )
		end
	elseif Key == "AllTalkPreGame" then
		if New or self.dt.AllTalk then
			self:UpdateAllTalk( self.dt.Gamestate )
		else
			self:RemoveAllTalkText()
		end
	end
end

function Plugin:ReceiveClientKicked( Data )
	local Key = Data.Reason ~= "" and "CLIENT_KICKED_REASON" or "CLIENT_KICKED"
	self:CommandNotify( Data.AdminName, Key, Data )
end

function Plugin:ReceiveChangeTeam( Data )
	self:CommandNotify( Data.AdminName, TeamChangeMessageKeys[ Data.Team ], Data )
end

function Plugin:SetupClientConfig()
	if self.Config.DisableLocalAllTalk then
		self:SendNetworkMessage( "EnableLocalAllTalk", { Enabled = false }, true )
	end

	self:BindCommand( "sh_alltalklocal_cl", function( Enable )
		if self:SetClientSetting( "DisableLocalAllTalk", not Enable ) then
			Print( "Local all talk is now %s.", Enable and "enabled" or "disabled" )
		end

		self:SendNetworkMessage( "EnableLocalAllTalk", { Enabled = Enable }, true )
	end ):AddParam{ Type = "boolean", Optional = true, Default = function() return self.Config.DisableLocalAllTalk end }

	self:AddClientSetting( "DisableLocalAllTalk", "sh_alltalklocal_cl", {
		Type = "Boolean",
		Description = "ALL_TALK_LOCAL_DESCRIPTION",
		Inverted = true
	} )
end

function Plugin:SetupAdminMenuCommands()
	local Category = self:GetPhrase( "CATEGORY" )

	self:AddAdminMenuCommand( Category, self:GetPhrase( "EJECT" ), "sh_eject", false, nil,
		self:GetPhrase( "EJECT_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "KICK" ), "sh_kick", false, {
		self:GetPhrase( "KICK_NO_REASON" ), "",
		self:GetPhrase( "KICK_TROLLING" ), "Trolling.",
		self:GetPhrase( "KICK_LANGUAGE" ), "Offensive language.",
		self:GetPhrase( "KICK_MIC_SPAM" ), "Mic spamming.",
		self:GetPhrase( "KICK_AFK" ), "AFK.",
		"Custom", {
			Setup = function( Menu, Command, Player, CleanupMenu )
				local Panel = SGUI:Create( "Panel", Menu )
				Panel:SetDebugName( "AdminMenuKickPlayerCustomReasonContainer" )

				local TextEntry = SGUI:Create( "TextEntry", Panel )
				TextEntry:SetDebugName( "AdminMenuKickPlayerCustomReasonTextEntry" )
				TextEntry:SetFill( true )
				TextEntry:SetPlaceholderText( self:GetPhrase( "KICK_CUSTOM" ) )
				TextEntry:SetFontScale( SGUI.FontManager.GetHighResFont( "kAgencyFB", 25 ) )
				function TextEntry:OnEnter()
					local Text = self:GetText()
					if #Text == 0 then return end

					Shine.AdminMenu:RunCommand( Command, StringFormat( "%s %s", Player, Text ) )
					CleanupMenu()
				end

				local Layout = SGUI.Layout:CreateLayout( "Horizontal", {
					Padding = SGUI.Layout.Units.Spacing( 2, 2, 2, 2 )
				} )
				Layout:AddElement( TextEntry )
				Panel:SetLayout( Layout )

				Menu:AddPanel( Panel )
			end
		},
		Width = 192
	}, self:GetPhrase( "KICK_TIP" ) )

	local GagTimes = {
		5 * 60, 10 * 60, 15 * 60, 20 * 60, 30 * 60
	}
	local GagLabels = {}
	for i = 1, #GagTimes do
		local Time = GagTimes[ i ]
		local TimeString = StringTimeToString( Time )

		GagLabels[ i * 2 - 1 ] = TimeString
		GagLabels[ i * 2 ] = tostring( Time )
	end

	GagLabels[ #GagLabels + 1 ] = self:GetPhrase( "GAG_UNTIL_MAP_CHANGE" )
	GagLabels[ #GagLabels + 1 ] = ""
	GagLabels[ #GagLabels + 1 ] = self:GetPhrase( "PERMANENTLY" )
	GagLabels[ #GagLabels + 1 ] = function( Args )
		if not StringMatch( Args, "^\"%d+\"$" ) then
			SGUI.NotificationManager.AddNotification( Shine.NotificationType.ERROR, self:GetPhrase( "ERROR_GAG_BOT" ), 5 )
			return
		end

		Shine.AdminMenu:RunCommand( "sh_gagid", Args )
	end

	self:AddAdminMenuCommand( Category, self:GetPhrase( "GAG" ), "sh_gag", false, GagLabels,
		self:GetPhrase( "GAG_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "UNGAG" ), "sh_ungag", false, nil,
		self:GetPhrase( "UNGAG_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "FORCE_RANDOM" ), "sh_forcerandom", true, nil,
		self:GetPhrase( "FORCE_RANDOM_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "READY_ROOM" ), "sh_rr", true, nil,
		self:GetPhrase( "READY_ROOM_TIP" ) )
	local Teams = {
		-- Ready room
		Shine:GetTeamName( 0, true ), "0",
		-- Marines
		Shine:GetTeamName( 1, true ), "1",
		self:GetInterpolatedPhrase( "FORCE_SET_TEAM", { TeamName = Shine:GetTeamName( 1, true ) } ), "1 true",
		-- Aliens
		Shine:GetTeamName( 2, true ), "2",
		self:GetInterpolatedPhrase( "FORCE_SET_TEAM", { TeamName = Shine:GetTeamName( 2, true ) } ), "2 true",
		-- Spectators
		Shine:GetTeamName( 3, true ), "3"
	}
	self:AddAdminMenuCommand( Category, self:GetPhrase( "SET_TEAM" ), "sh_setteam", true, Teams,
		self:GetPhrase( "SET_TEAM_TIP" ) )

	local Units = SGUI.Layout.Units
	local HighResScaled = Units.HighResScaled
	local Percentage = Units.Percentage
	local Spacing = Units.Spacing
	local UnitVector = Units.UnitVector
	local Auto = Units.Auto

	self:AddAdminMenuTab( self:GetPhrase( "MAPS" ), {
		Icon = SGUI.Icons.Ionicons.Earth,
		OnInit = function( Panel, Data )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 28 ),
					HighResScaled( 16 ), HighResScaled( 16 ) )
			} )

			local List = SGUI:Create( "List", Panel )
			List:SetDebugName( "AdminMenuMapsList" )
			List:SetColumns( self:GetPhrase( "MAP" ) )
			List:SetSpacing( 1 )
			List:SetFill( true )

			Shine.AdminMenu.SetupListWithScaling( List )

			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

			Layout:AddElement( List )

			self.MapList = List

			local ControlLayout = SGUI.Layout:CreateLayout( "Horizontal", {
				Margin = Spacing( 0, HighResScaled( 16 ), 0, 0 ),
				Fill = false
			} )

			local ChangeMap = SGUI:Create( "Button", Panel )
			ChangeMap:SetDebugName( "AdminMenuChangeMapButton" )
			ChangeMap:SetText( self:GetPhrase( "CHANGE_MAP" ) )
			ChangeMap:SetFontScale( Font, Scale )
			ChangeMap:SetIcon( SGUI.Icons.Ionicons.ArrowRightC )
			ChangeMap:SetStyleName( "DangerButton" )
			function ChangeMap.DoClick()
				local Selected = List:GetSelectedRow()
				if not Selected then return end

				local Map = Selected:GetColumnText( 1 )

				Shine.AdminMenu:RunCommand( "sh_changelevel", Map )
			end
			ChangeMap:SetTooltip( self:GetPhrase( "CHANGE_MAP_TIP" ) )
			ChangeMap:SetEnabled( List:HasSelectedRow() )

			ControlLayout:AddElement( ChangeMap )

			function List:OnRowSelected( Index, Row )
				ChangeMap:SetEnabled( true )
			end

			function List:OnRowDeselected( Index, Row )
				ChangeMap:SetEnabled( false )
			end

			local ButtonWidth = Units.Max(
				HighResScaled( 128 ),
				Auto( ChangeMap ) + HighResScaled( 16 )
			)

			ChangeMap:SetAutoSize( UnitVector( ButtonWidth, Percentage.ONE_HUNDRED ) )

			if Shine:IsExtensionEnabled( "mapvote" ) then
				local CallVote = SGUI:Create( "Button", Panel )
				CallVote:SetDebugName( "AdminMenuCallMapVoteButton" )
				CallVote:SetText( self:GetPhrase( "CALL_VOTE" ) )
				CallVote:SetFontScale( Font, Scale )
				CallVote:SetAlignment( SGUI.LayoutAlignment.MAX )
				CallVote:SetIcon( SGUI.Icons.Ionicons.Speakerphone )
				function CallVote.DoClick()
					Shine.AdminMenu:RunCommand( "sh_forcemapvote" )
				end
				CallVote:SetTooltip( self:GetPhrase( "CALL_VOTE_TIP" ) )
				CallVote:SetAutoSize( UnitVector( ButtonWidth, Percentage.ONE_HUNDRED ) )

				ButtonWidth:AddValue( Auto( CallVote ) + HighResScaled( 16 ) )

				ControlLayout:AddElement( CallVote )
			end

			local ButtonHeight = Auto( ChangeMap ) + HighResScaled( 8 )
			ControlLayout:SetAutoSize( UnitVector( Percentage.ONE_HUNDRED, ButtonHeight ) )

			Layout:AddElement( ControlLayout )
			Panel:SetLayout( Layout )
			Panel:InvalidateLayout( true )

			if not self.MapData then
				self:RequestMapData()
			else
				for Map in pairs( self.MapData ) do
					List:AddRow( Map )
				end
			end

			if not Shine.AdminMenu.RestoreListState( List, Data ) then
				List:SortRows( 1 )
			end
		end,

		OnCleanup = function( Panel )
			local MapList = self.MapList
			self.MapList = nil

			return Shine.AdminMenu.GetListState( MapList )
		end
	} )

	local AgencyFBNormal = {
		Family = "kAgencyFB",
		Size = HighResScaled( 27 )
	}
	local Ionicons = {
		Family = SGUI.FontFamilies.Ionicons,
		Size = HighResScaled( 27 )
	}
	local StateColours = {
		[ true ] = Colour( 0, 0.7, 0 ),
		[ false ] = Colour( 1, 0.6, 0 )
	}
	local StateIcons = {
		[ true ] = SGUI.Icons.Ionicons.CheckmarkCircled,
		[ false ] = SGUI.Icons.Ionicons.MinusCircled
	}

	local PluginEntry = SGUI:DefineControl( "PluginEntry", "Row" )
	SGUI.AddProperty( PluginEntry, "Enabled" )
	SGUI.AddProperty( PluginEntry, "ConfiguredAsEnabled" )

	function PluginEntry:SetPluginData( PluginData )
		self:SetEnabled( PluginData.Enabled )
		self:SetConfiguredAsEnabled( PluginData.ConfiguredAsEnabled )

		local RowElements = {
			{
				Class = "Label",
				Props = {
					AutoFont = AgencyFBNormal,
					Text = PluginData.Name
				}
			}
		}

		if PluginData.IsOfficial then
			RowElements[ #RowElements + 1 ] = {
				Class = "Label",
				Props = {
					AutoFont = Ionicons,
					Margin = Spacing( HighResScaled( 8 ), 0, 0, 0 ),
					StyleName = "InfoLabel",
					Text = SGUI.Icons.Ionicons.AndroidCheckmarkCircle,
					Tooltip = Shine.Locale:GetPhrase( "Core", "OFFICIAL_PLUGIN_TOOLTIP" )
				}
			}
		end

		local ButtonSize = HighResScaled( 32 )
		local function GetSaveButtonTooltip( Enabled, ConfiguredAsEnabled )
			if ConfiguredAsEnabled ~= Enabled then
				return Plugin:GetPhrase(
					Enabled and "LOAD_PLUGIN_SAVE_TIP" or "UNLOAD_PLUGIN_SAVE_TIP"
				)
			end
			return Plugin:GetPhrase(
				Enabled and "PLUGIN_SAVED_AS_ENABLED" or "PLUGIN_SAVED_AS_DISABLED"
			)
		end

		RowElements[ #RowElements + 1 ] = {
			ID = "SaveButton",
			Class = "Button",
			Props = {
				Alignment = SGUI.LayoutAlignment.MAX,
				AutoSize = UnitVector( ButtonSize, ButtonSize ),
				Horizontal = true,
				Icon = SGUI.Icons.Ionicons.Locked,
				IconAutoFont = Ionicons,
				Margin = Spacing( HighResScaled( 4 ), 0, 0, 0 )
			},
			Bindings = {
				{
					From = {
						Element = self,
						Property = "ConfiguredAsEnabled"
					},
					To = {
						{
							Property = "Enabled",
							Transformer = function( ConfiguredAsEnabled )
								if
									( ConfiguredAsEnabled and self.Enabled ) or
									( not ConfiguredAsEnabled and not self.Enabled )
								then
									return false
								end
								return true
							end
						},
						{
							Property = "Tooltip",
							Transformer = function( ConfiguredAsEnabled )
								return GetSaveButtonTooltip( self.Enabled, ConfiguredAsEnabled )
							end
						}
					}
				},
				{
					From = {
						Element = self,
						Property = "Enabled"
					},
					To = {
						{
							Property = "Enabled",
							Transformer = function( Enabled )
								if
									( self.ConfiguredAsEnabled and Enabled ) or
									( not self.ConfiguredAsEnabled and not Enabled )
								then
									return false
								end
								return true
							end
						},
						{
							Property = "Tooltip",
							Transformer = function( Enabled )
								return GetSaveButtonTooltip( Enabled, self.ConfiguredAsEnabled )
							end
						}
					}
				}
			}
		}
		RowElements[ #RowElements + 1 ] = {
			ID = "ToggleButton",
			Class = "Button",
			Props = {
				Alignment = SGUI.LayoutAlignment.MAX,
				AutoSize = UnitVector( ButtonSize, ButtonSize ),
				Horizontal = true,
				IconAutoFont = Ionicons,
				Margin = Spacing( HighResScaled( 4 ), 0, 0, 0 )
			},
			Bindings = {
				{
					From = {
						Element = self,
						Property = "Enabled"
					},
					To = {
						{
							Property = "Icon",
							Transformer = function( Enabled )
								return SGUI.Icons.Ionicons[ Enabled and "Close" or "Power" ]
							end
						},
						{
							Property = "StyleName",
							Transformer = function( Enabled ) return Enabled and "DangerButton" or "SuccessButton" end
						},
						{
							Property = "Tooltip",
							Transformer = function( Enabled )
								return Plugin:GetPhrase( Enabled and "UNLOAD_PLUGIN" or "LOAD_PLUGIN" )
							end
						}
					}
				}
			}
		}
		RowElements[ #RowElements + 1 ] = {
			ID = "ReloadButton",
			Class = "Button",
			Props = {
				Alignment = SGUI.LayoutAlignment.MAX,
				AutoSize = UnitVector( ButtonSize, ButtonSize ),
				Horizontal = true,
				Icon = SGUI.Icons.Ionicons.Refresh,
				IconAutoFont = Ionicons,
				Margin = Spacing( HighResScaled( 4 ), 0, 0, 0 ),
				Tooltip = Plugin:GetPhrase( "RELOAD_PLUGIN" )
			},
			Bindings = {
				{
					From = {
						Element = self,
						Property = "Enabled"
					},
					To = {
						Property = "IsVisible"
					}
				}
			}
		}

		local Elements = SGUI:BuildTree( {
			Parent = self,
			{
				ID = "StatusFlair",
				Class = "Column",
				Props = {
					AutoSize = UnitVector( Auto.INSTANCE, 0 ),
					Padding = Spacing( HighResScaled( 4 ), 0, HighResScaled( 4 ), 0 ),
					IsSchemed = false
				},
				Children = {
					{
						Class = "Label",
						Props = {
							Alignment = SGUI.LayoutAlignment.CENTRE,
							AutoFont = Ionicons,
							CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
							IsSchemed = false,
							Colour = Colour( 1, 1, 1 )
						},
						Bindings = {
							{
								From = {
									Element = self,
									Property = "Enabled"
								},
								To = {
									Property = "Text",
									Transformer = function( Enabled ) return StateIcons[ Enabled ] end
								}
							}
						}
					}
				},
				Bindings = {
					{
						From = {
							Element = self,
							Property = "Enabled"
						},
						To = {
							{
								Property = "Colour",
								Transformer = function( Enabled ) return StateColours[ Enabled ] end
							},
							{
								Property = "Tooltip",
								Transformer = function( Enabled )
									return Shine.Locale:GetPhrase( "Core", Enabled and "ENABLED" or "DISABLED" )
								end
							}
						}
					}
				}
			},
			{
				ID = "Content",
				Class = "Horizontal",
				Type = "Layout",
				Props = {
					Padding = Spacing.Uniform( HighResScaled( 8 ) )
				},
				Children = RowElements
			},
			OnBuilt = function( Elements )
				Elements.StatusFlair.AutoSize[ 2 ] = Units.Auto( Elements.Content )
			end
		} )

		TableShallowMerge( Elements, self )

		function self.ReloadButton.DoClick()
			Shine.AdminMenu:RunCommand( "sh_loadplugin", PluginData.Name )
		end

		function self.ToggleButton.DoClick()
			if self.Enabled then
				Shine.AdminMenu:RunCommand( "sh_unloadplugin", PluginData.Name )
			else
				Shine.AdminMenu:RunCommand( "sh_loadplugin", PluginData.Name )
			end
		end

		function self.SaveButton.DoClick()
			-- The save flag here doesn't cause any attempt to load/unload unless the plugin isn't in the expected
			-- state, so this won't unexpectedly reload a plugin.
			if self.Enabled then
				Shine.AdminMenu:RunCommand( "sh_loadplugin", PluginData.Name.." true" )
			else
				Shine.AdminMenu:RunCommand( "sh_unloadplugin", PluginData.Name.." true" )
			end
		end

		self:SetColour( Colour( 0, 0, 0, 0.15 ) )
	end

	local function IsClientOnlyPlugin( PluginTable )
		return PluginTable.IsClient and not PluginTable.IsShared
	end

	function self:PopulatePluginList()
		local Panel = self.PluginPanel
		if not SGUI.IsValid( Panel ) then return end

		local Rows = {
			Parent = Panel
		}
		local RowMargin = HighResScaled( 8 )

		for Plugin in pairs( Shine.AllPlugins ) do
			local Enabled, PluginTable = Shine:IsExtensionEnabled( Plugin )

			-- Ignore client-side only plugins, they're managed in the client config menu per player.
			if not PluginTable or not IsClientOnlyPlugin( PluginTable ) then
				local PluginData = self.PluginData and self.PluginData[ Plugin ]
				Rows[ #Rows + 1 ] = {
					ID = Plugin,
					Class = PluginEntry,
					Props = {
						AutoSize = UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ),
						DebugName = StringFormat( "AdminMenu%sPluginRow", Plugin ),
						Margin = Spacing( 0, 0, 0, RowMargin ),
						PluginData = PluginData or {
							Name = Plugin,
							Enabled = Enabled,
							ConfiguredAsEnabled = false,
							IsOfficial = Shine.IsOfficialExtension( Plugin )
						}
					}
				}
			end
		end

		TableSort( Rows, function( A, B )
			return A.ID < B.ID
		end )

		local LastRow = Rows[ #Rows ]
		if LastRow then
			LastRow.Props.Margin = nil
		end

		self.PluginRows = SGUI:BuildTree( Rows )
	end

	self:AddAdminMenuTab( self:GetPhrase( "PLUGINS" ), {
		Icon = SGUI.Icons.Ionicons.Settings,
		OnInit = function( Panel, Data )
			self.PluginRows = self.PluginRows or {}

			-- We need information about the server side only plugins too.
			if not self.PluginData then
				self:RequestPluginData()
				self.PluginData = {}
			end

			local function UpdateRow( Name, State )
				local Row = self.PluginRows[ Name ]
				if SGUI.IsValid( Row ) then
					Row:SetEnabled( State )
				end
			end

			Hook.Add( "OnPluginLoad", "AdminMenu_OnPluginLoad", function( Name, Plugin, Shared )
				UpdateRow( Name, true )
			end )

			Hook.Add( "OnPluginUnload", "AdminMenu_OnPluginUnload", function( Name, Plugin, Shared )
				UpdateRow( Name, false )
			end )

			local Elements = SGUI:BuildTree( {
				Parent = Panel,
				{
					Class = "Vertical",
					Type = "Layout",
					Props = {
						Padding = Spacing(
							HighResScaled( 16 ), HighResScaled( 28 ), HighResScaled( 16 ), HighResScaled( 16 )
						)
					},
					Children = {
						{
							Class = "Horizontal",
							Type = "Layout",
							Props = {
								AutoSize = UnitVector( Percentage.ONE_HUNDRED, Auto.INSTANCE ),
								Fill = false,
								Margin = Spacing( 0, 0, 0, HighResScaled( 8 ) )
							},
							Children = {
								{
									Class = "Label",
									Props = {
										AutoFont = Ionicons,
										Text = SGUI.Icons.Ionicons.Search,
										Margin = Spacing( 0, 0, HighResScaled( 8 ), 0 )
									}
								},
								{
									ID = "SearchEntry",
									Class = "TextEntry",
									Props = {
										AutoFont = AgencyFBNormal,
										AutoSize = UnitVector( 0, Auto.INSTANCE ),
										Fill = true,
										PlaceholderText = self:GetPhrase( "SEARCH_PLUGINS_HINT" )
									}
								},
							}
						},
						{
							ID = "PluginPanel",
							Class = "Column",
							Props = {
								Scrollable = true,
								Fill = true,
								Colour = Colour( 0, 0, 0, 0 ),
								ScrollbarPos = Vector2( 0, 0 ),
								ScrollbarWidth = HighResScaled( 8 ):GetValue(),
								ScrollbarHeightOffset = 0
							}
						}
					}
				}
			} )

			function Elements.SearchEntry.OnTextChanged( SearchEntry, OldText, NewText )
				for Plugin, Row in pairs( self.PluginRows ) do
					Row:SetIsVisible( NewText == "" or not not StringFind( Plugin, NewText, 1, true ) )
				end
			end

			self.PluginPanel = Elements.PluginPanel

			if self.PluginAuthed then
				self:PopulatePluginList()
			end
		end,

		OnCleanup = function( Panel )
			self.PluginRows = nil
			self.PluginList = nil

			Hook.Remove( "OnPluginLoad", "AdminMenu_OnPluginLoad" )
			Hook.Remove( "OnPluginUnload", "AdminMenu_OnPluginUnload" )
		end
	} )
end

function Plugin:RequestMapData()
	self:SendNetworkMessage( "RequestMapData", {}, true )
end

function Plugin:ReceiveMapData( Data )
	self.MapData = self.MapData or {}

	if self.MapData[ Data.Name ] then return end

	self.MapData[ Data.Name ] = true

	if SGUI.IsValid( self.MapList ) then
		self.MapList:AddRow( Data.Name )
	end
end

function Plugin:RequestPluginData()
	self:SendNetworkMessage( "RequestPluginData", {}, true )
end

function Plugin:ReceivePluginTabAuthed()
	self.PluginAuthed = true
	self:PopulatePluginList()
end

function Plugin:ReceivePluginData( Data )
	self.PluginData = self.PluginData or {}
	self.PluginData[ Data.Name ] = Data
	Data.IsOfficial = Shine.IsOfficialExtension( Data.Name )

	local Row = self.PluginRows[ Data.Name ]
	if Row then
		Row:SetEnabled( Data.Enabled )
		Row:SetConfiguredAsEnabled( Data.ConfiguredAsEnabled )
	end
end

local NOT_STARTED = kGameState and kGameState.WarmUp or 2
local COUNTDOWN = kGameState and kGameState.Countdown or 4

function Plugin:UpdateAllTalk( State )
	if not self.dt.AllTalk and not self.dt.AllTalkPreGame then return end

	if State >= COUNTDOWN and not self.dt.AllTalk then
		self:RemoveAllTalkText()
		return
	end

	local Phrase
	local AllTalkIsDisabled = State > NOT_STARTED and not self.dt.AllTalk
	if AllTalkIsDisabled then
		Phrase = self:GetPhrase( "ALLTALK_DISABLED" )
	else
		Phrase = self:GetPhrase( "ALLTALK_ENABLED" )
	end

	if not self.TextObj then
		local GB = AllTalkIsDisabled and 0 or 255

		self.TextObj = Shine.ScreenText.Add( "AllTalkState", {
			X = 0.5, Y = 0.95,
			Text = Phrase,
			R = 255, G = GB, B = GB,
			Alignment = 1,
			Size = 2,
			FadeIn = 1,
			IgnoreFormat = true,
			UpdateRate = 0.1
		} )

		function self.TextObj:UpdateForInventoryState( IsAlwaysVisible )
			if IsAlwaysVisible and not self.SetupForVisibleInventory then
				-- Inventory is always visible, so move text to the top of the screen
				-- (some configurations have a giant inventory that extends to the bottom
				-- of the screen, and the inventory position doesn't account for ammo text).
				self.SetupForVisibleInventory = true
				self:SetIsVisible( true )
				self:SetScaledPos( self.x, 0.075 )
			elseif not IsAlwaysVisible and self.SetupForVisibleInventory then
				-- Inventory is only visible when in use, so we'll hide the text.
				self.SetupForVisibleInventory = false
				self:SetScaledPos( self.x, 0.95 )
			end
		end

		-- Hide the text if the inventory HUD is visible (avoids the text overlapping it).
		-- There's no easy way to determine its visibility, so this awkward polling will have to do.
		function self.TextObj:Think()
			-- Allow other mods to influence the position and visiblity of the text if they have
			-- extra HUD elements. Should return whether the text is visible, and its new position.
			local Visible, X, Y = Hook.Call( "OnUpdateAllTalkText", self:GetIsVisible(), self.x, self.y )
			if Visible ~= nil then
				self:SetIsVisible( Visible )
				if X and self.x ~= X or Y and self.y ~= Y then
					self:SetScaledPos( X or self.x, Y or self.y )
				end
				return
			end

			local HUD = ClientUI.GetScript( "Hud/Marine/GUIMarineHUD" ) or ClientUI.GetScript( "GUIAlienHUD" )
			local Inventory = HUD and HUD.inventoryDisplay
			local InventoryIsVisible = Inventory and Inventory.background and Inventory.background:GetIsVisible()

			if not ( InventoryIsVisible and Inventory.inventoryIcons ) then
				self:SetIsVisible( true )
				self:UpdateForInventoryState( false )
				return
			end

			if Inventory.forceAnimationReset then
				self:UpdateForInventoryState( true )

				return
			end

			self:UpdateForInventoryState( false )

			local Items = Inventory.inventoryIcons
			for i = 1, #Items do
				local Item = Items[ i ]
				if Item and Item.Graphic and Item.Graphic:GetColor().a > 0 then
					-- Inventory is temporarily visible, hide the text.
					self:SetIsVisible( false )
					return
				end
			end

			-- Inventory is not visible, show the text.
			self:SetIsVisible( true )
		end

		return
	end

	self.TextObj.Text = Phrase
	self.TextObj:UpdateText()

	local Col = AllTalkIsDisabled and Color( 255, 0, 0 ) or Color( 255, 255, 255 )

	self.TextObj:SetColour( Col )
end

function Plugin:RemoveAllTalkText()
	if not self.TextObj then return end

	self.TextObj:End()
	self.TextObj = nil
end

function Plugin:Cleanup()
	self:RemoveAllTalkText()

	self.BaseClass.Cleanup( self )
end
