--[[
	Clientside configuration menu.
]]

local Binder = require "shine/lib/gui/binding/binder"

local SGUI = Shine.GUI
local Locale = Shine.Locale

local IsType = Shine.IsType
local StringFormat = string.format

local ConfigMenu = {}
SGUI:AddMixin( ConfigMenu, "Visibility" )

Shine.ConfigMenu = ConfigMenu

ConfigMenu.Tabs = {}

local Units = SGUI.Layout.Units
local HighResScaled = Units.HighResScaled
local Percentage = Units.Percentage
local Spacing = Units.Spacing
local UnitVector = Units.UnitVector

local SMALL_PADDING = HighResScaled( 8 )

ConfigMenu.Size = UnitVector( Units.Integer( HighResScaled( 800 ) ), Units.Integer( HighResScaled( 600 ) ) )
ConfigMenu.EasingTime = 0.25

local function NeedsToScale()
	local W, H = SGUI.GetScreenSize()
	return H > 1080
end

local function GetSmallFont()
	if NeedsToScale() then
		return SGUI.FontManager.GetFont( "kAgencyFB", 27 )
	end

	return Fonts.kAgencyFB_Small
end

local function GetMediumFont()
	if NeedsToScale() then
		return SGUI.FontManager.GetFont( "kAgencyFB", 33 )
	end

	return Fonts.kAgencyFB_Medium
end

function ConfigMenu:Create()
	if self.Menu then return end

	self.Menu = SGUI:Create( "TabPanel" )
	self.Menu:SetDebugName( "ClientConfigMenuWindow" )
	self.Menu:SetAnchor( "CentreMiddle" )
	self.Menu:SetAutoSize( self.Size, true )

	self.Menu:SetTabWidth( Units.Integer( HighResScaled( 128 ) ):GetValue() )
	self.Menu:SetTabHeight( Units.Integer( HighResScaled( 40 ) ):GetValue() )
	self.Menu:SetFontScale( GetSmallFont() )

	self.Pos = self.Menu:GetSize() * -0.5
	self.Menu:SetPos( self.Pos )

	self.Menu:CallOnRemove( function()
		if self.IgnoreRemove then return end

		if self.Visible then
			-- Make sure mouse is disabled in case of error.
			SGUI:EnableMouse( false )
			self.Visible = false
		end

		self.Menu = nil
	end )

	self.Menu.OnPreTabChange = function( Window )
		if not Window.ActiveTab then return end

		local Tab = self.Tabs[ Window.ActiveTab ]
		if not Tab or not Tab.OnCleanup then return end

		Tab.Data = Tab.OnCleanup( Window.ContentPanel )
	end

	self.Menu:SetExpanded( Shine.Config.ExpandConfigMenuTabs )
	self.Menu:AddPropertyChangeListener( "Expanded", function( Menu, Expanded )
		Shine:SetClientSetting( "ExpandConfigMenuTabs", Expanded )
	end )

	self.Menu.TitleBarHeight = HighResScaled( 24 ):GetValue()
	self:PopulateTabs( self.Menu )

	self.Menu:AddCloseButton()
	self.Menu.OnClose = function()
		self:ForceHide()
		return true
	end

	self.Menu:SetBoxShadow( {
		BlurRadius = 16,
		Colour = Colour( 0, 0, 0, 0.75 )
	} )
end

function ConfigMenu:Close()
	if not self.Menu or not self.Visible then return end

	self.Menu:Close()
end

Shine.Hook.Add( "OnResolutionChanged", ConfigMenu, function()
	if not ConfigMenu.Menu then return end

	ConfigMenu.IgnoreRemove = true
	ConfigMenu.Menu:Destroy()
	ConfigMenu.IgnoreRemove = false
	ConfigMenu.Menu = nil

	if ConfigMenu.Visible then
		ConfigMenu:Create()
	end
end )

Shine.Hook.Add( "PlayerKeyPress", ConfigMenu, function( Key, Down )
	return Shine.AdminMenu.PlayerKeyPress( ConfigMenu, Key, Down )
end, 1 )

-- Close when logging in/out of a command structure to avoid mouse problems.
Shine.Hook.Add( "OnCommanderLogout", ConfigMenu, function()
	ConfigMenu:Close()
end )
Shine.Hook.Add( "OnCommanderLogin", ConfigMenu, function()
	ConfigMenu:Close()
end )

-- Ensure the settings tab updates when settings are added/removed by plugins.
Shine.Hook.Add( "OnClientSettingAdded", ConfigMenu, function( Entry )
	ConfigMenu:RefreshSettings()
end )
Shine.Hook.Add( "OnClientSettingRemoved", ConfigMenu, function( Entry )
	ConfigMenu:RefreshSettings()
end )

function ConfigMenu:SetIsVisible( Bool, IgnoreAnim )
	if self.Visible == Bool then return end

	if not self.Menu then
		self:Create()
	end

	Shine.AdminMenu.AnimateVisibility( self.Menu, Bool, self.Visible, self.EasingTime, self.Pos, IgnoreAnim )

	self.Visible = Bool

	Shine.Hook.Broadcast( "OnConfigMenuVisibilityChanged", self, Bool )
end

function ConfigMenu:GetIsVisible()
	return self.Visible or false
end

ConfigMenu:BindVisibilityToEvents( "OnHelpScreenDisplay", "OnHelpScreenHide" )

function ConfigMenu:PopulateTabs( Menu )
	local Tabs = self.Tabs
	for i = 1, #Tabs do
		local Tab = Tabs[ i ]
		local TabEntry = Menu:AddTab( Tab.Name, function( Panel )
			Tab.OnInit( Panel, Tab.Data )
		end, Tab.Icon )
	end
end

function ConfigMenu:AddTab( Name, Tab )
	if self.Tabs[ Name ] then return end

	Tab.Name = Name
	self.Tabs[ Name ] = Tab
	self.Tabs[ #self.Tabs + 1 ] = Tab
end

function ConfigMenu:RefreshSettings()
	if not SGUI.IsValid( self.Menu ) then return end

	-- Delay by a frame to avoid bursts of new/removed settings when plugins are enabled/disabled.
	self.RefreshTimer = self.RefreshTimer or Shine.Timer.Simple( 0, function()
		self.RefreshTimer = nil

		if not SGUI.IsValid( self.Menu ) then return end

		self.Menu:ForceTabRefresh( 1 )
	end )
	self.RefreshTimer:Debounce()
end

function ConfigMenu:OpenOnSettingsTab( TabName )
	self:SetIsVisible( true )

	if not SGUI.IsValid( self.Menu ) then return end

	self.Menu:SetSelectedTab( self.Menu.Tabs[ 1 ] )

	if not SGUI.IsValid( self.SettingsTabs ) then return end

	local Tabs = self.SettingsTabs.Tabs
	for i = 1, #Tabs do
		local Tab = Tabs[ i ]
		if Tab.TabButton:GetText() == TabName then
			self.SettingsTabs:SetSelectedTab( Tab )
			break
		end
	end
end

local function GetConfiguredValue( Entry )
	local Value
	if IsType( Entry.ConfigOption, "string" ) then
		Value = Shine.Config[ Entry.ConfigOption ]
	else
		Value = Entry.ConfigOption()
	end
	return Value
end

local function MakeElementWithDescription( Panel, Entry, Populator )
	local Container = Panel:Add( "Panel" )
	Container:SetStyleName( "RadioBackground" )
	Container:SetAutoSize( UnitVector(
		Percentage.ONE_HUNDRED,
		Units.Auto.INSTANCE
	) )

	local TranslationSource = Entry.TranslationSource or "Core"
	local VerticalLayout = SGUI.Layout:CreateLayout( "Vertical" )

	local Description = Container:Add( "Label" )
	Description:SetFontScale( GetSmallFont() )
	Description:SetText( Locale:GetPhrase( TranslationSource, Entry.Description ) )
	Description:SetAutoSize( UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ) )
	Description:SetMargin( Spacing( 0, 0, 0, SMALL_PADDING ) )
	VerticalLayout:AddElement( Description )

	local ValueHolder = Populator( Entry, TranslationSource, Container, VerticalLayout )

	Container:SetLayout( VerticalLayout, true )

	return Container, ValueHolder
end

local SettingsTypes = {
	Boolean = {
		Create = function( Panel, Entry )
			local CheckBox = Panel:Add( "CheckBox" )
			CheckBox:SetFontScale( GetSmallFont() )
			CheckBox:AddLabel( Locale:GetPhrase( Entry.TranslationSource or "Core", Entry.Description ) )
			CheckBox:SetAutoSize( UnitVector( HighResScaled( 24 ), HighResScaled( 24 ) ) )

			local Enabled = GetConfiguredValue( Entry )
			if Entry.Inverted then
				Enabled = not Enabled
			end

			CheckBox:SetChecked( not not Enabled, true )
			CheckBox.OnChecked = function( CheckBox, Value )
				Shared.ConsoleCommand( Entry.Command.." "..tostring( Value ) )
			end

			return CheckBox, CheckBox
		end,
		Update = function( ValueHolder, NewValue )
			ValueHolder:SetChecked( not not NewValue )
		end
	},
	Slider = {
		Create = function( Panel, Entry )
			return MakeElementWithDescription( Panel, Entry, function( Entry, TranslationSource, Container, VerticalLayout )
				local Slider = Container:Add( "Slider" )
				Slider:SetFontScale( GetSmallFont() )
				Slider:SetBounds( Entry.Min, Entry.Max )
				Slider:SetDecimals( Entry.Decimals or 0 )

				Slider:SetAutoSize( UnitVector( Percentage.ONE_HUNDRED - HighResScaled( 64 ), HighResScaled( 32 ) ) )

				function Slider:OnValueChanged( Value )
					Shared.ConsoleCommand( StringFormat( "%s %s", Entry.Command, Value ) )
				end
				VerticalLayout:AddElement( Slider )

				local CurrentValue = GetConfiguredValue( Entry )
				Slider:SetValue( CurrentValue, true )

				return Slider
			end )
		end,
		Update = function( ValueHolder, NewValue )
			ValueHolder:SetValue( NewValue, true )
		end
	},
	Dropdown = {
		Create = function( Panel, Entry )
			return MakeElementWithDescription( Panel, Entry, function( Entry, TranslationSource, Container, VerticalLayout )
				local Dropdown = Container:Add( "Dropdown" )
				Dropdown:SetFontScale( GetSmallFont() )
				Dropdown:AddOptions( Shine.IsCallable( Entry.Options ) and Entry.Options() or Entry.Options )
				Dropdown:SetAutoSize( UnitVector( Percentage.ONE_HUNDRED, HighResScaled( 32 ) ) )
				VerticalLayout:AddElement( Dropdown )

				local CurrentValue = GetConfiguredValue( Entry )
				Dropdown:SelectOption( CurrentValue )

				Dropdown:AddPropertyChangeListener( "SelectedOption", function( Dropdown, Option )
					Shared.ConsoleCommand( Entry.Command.." "..( Option.Value or Option.Text ) )
				end )

				return Dropdown
			end )
		end,
		Update = function( ValueHolder, NewValue )
			ValueHolder:SelectOption( NewValue )
		end
	},
	Radio = {
		Create = function( Panel, Entry )
			return MakeElementWithDescription( Panel, Entry, function( Entry, TranslationSource, Container, VerticalLayout )
				local Radio = Container:Add( "Radio" )
				Radio:SetAutoSize( UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ) )
				Radio:SetFontScale( GetSmallFont() )
				Radio:SetCheckBoxAutoSize( UnitVector( HighResScaled( 24 ), HighResScaled( 24 ) ) )
				Radio:SetCheckBoxMargin( Spacing( 0, HighResScaled( 4 ), 0, 0 ) )

				local CurrentChoice = GetConfiguredValue( Entry )
				local OptionsByValue = {}
				for i = 1, #Entry.Options do
					local Option = Entry.Options[ i ]

					local Tooltip
					if IsType( Entry.OptionTooltips, "table" )
					and IsType( Entry.OptionTooltips[ Option ], "string" ) then
						Tooltip = Locale:GetPhrase( TranslationSource, Entry.OptionTooltips[ Option ] )
					end

					local RadioOption = {
						Description = Locale:GetPhrase( TranslationSource, Option ),
						Value = Option,
						Tooltip = Tooltip
					}
					OptionsByValue[ Option ] = RadioOption
					Radio:AddOption( RadioOption )

					if CurrentChoice == Option then
						Radio:SetSelectedOption( RadioOption, true )
					end
				end

				Radio.OptionsByValue = OptionsByValue
				Radio:AddPropertyChangeListener( "SelectedOption", function( Dropdown, Option )
					Shared.ConsoleCommand( Entry.Command.." "..Option.Value )
				end )

				VerticalLayout:AddElement( Radio )

				return Radio
			end )
		end,
		Update = function( ValueHolder, NewValue )
			ValueHolder:SetSelectedOption( ValueHolder.OptionsByValue[ NewValue ] )
		end
	}
}

ConfigMenu:AddTab( Locale:GetPhrase( "Core", "SETTINGS_TAB" ), {
	Icon = SGUI.Icons.Ionicons.GearB,
	OnInit = function( Panel, Data )
		local Settings = Shine.ClientSettings
		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Spacing( SMALL_PADDING, SMALL_PADDING,
				SMALL_PADDING, SMALL_PADDING )
		} )

		local Title = Panel:Add( "Label" )
		Title:SetFontScale( GetMediumFont() )
		Title:SetText( Locale:GetPhrase( "Core", "CLIENT_SETTINGS" ) )
		Title:SetMargin( Spacing( 0, 0, 0, HighResScaled( 7 ) ) )
		Layout:AddElement( Title )

		local SettingsByGroup = Shine.Multimap()
		local GeneralGroup = {
			Key = "GENERAL_CLIENT_SETTINGS",
			Source = "Core",
			Icon = SGUI.Icons.Ionicons.GearA
		}
		local Groups = {}

		local TabWidth = Units.Max()

		local Tabs = Panel:Add( "TabPanel" )
		Tabs:SetFill( true )
		Tabs:SetTabWidth( TabWidth )
		Tabs:SetTabHeight( HighResScaled( 36 ):GetValue() )
		Tabs:SetFontScale( SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 ) )
		Tabs:SetHorizontal( true )

		Panel.SettingsTabs = Tabs
		ConfigMenu.SettingsTabs = Tabs

		for i = 1, #Settings do
			local Setting = Settings[ i ]
			local Creator = SettingsTypes[ Setting.Type ]
			local Group = Setting.Group or GeneralGroup

			if Creator then
				local GroupName = Locale:GetPhrase( Group.Source, Group.Key )
				Groups[ GroupName ] = Group

				SettingsByGroup:Add( GroupName, Setting )
			end
		end

		-- Sort the tabs to keep the general tab at the front, then order the rest alphabetically.
		-- This accounts for plugins loading/unloading after the menu is created, which can alter the order of
		-- the settings list above.
		local GeneralGroupName = Locale:GetPhrase( GeneralGroup.Source, GeneralGroup.Key )
		SettingsByGroup:SortKeys( function( A, B )
			if A == GeneralGroupName then
				if B == GeneralGroupName then
					return false
				end
				return true
			end

			if B == GeneralGroupName then
				return false
			end

			return A < B
		end )

		local function SetupTabPanel( TabPanel )
			TabPanel:SetScrollable()
			TabPanel:SetScrollbarWidth( SMALL_PADDING:GetValue() )
			TabPanel:SetScrollbarPos( Vector2( -SMALL_PADDING:GetValue(), 0 ) )
			TabPanel:SetScrollbarHeightOffset( 0 )
			TabPanel:SetResizeLayoutForScrollbar( true )

			return SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( SMALL_PADDING, SMALL_PADDING,
					SMALL_PADDING, SMALL_PADDING )
			} )
		end

		for Group, Settings in SettingsByGroup:Iterate() do
			local GroupDef = Groups[ Group ]
			local Tab = Tabs:AddTab( Group, function( TabPanel )
				local TabLayout = SetupTabPanel( TabPanel )
				local ElementsByKey = {}
				local SettingsWithBindings = {}
				local Dropdowns = {}

				for i = 1, #Settings do
					local Setting = Settings[ i ]
					local Creator = SettingsTypes[ Setting.Type ]

					local Object, ValueHolder = Creator.Create( TabPanel, Setting )

					if Setting.Type == "Dropdown" then
						Dropdowns[ #Dropdowns + 1 ] = ValueHolder
					end

					local TranslationSource = Setting.TranslationSource or "Core"
					if IsType( Setting.Tooltip, "string" ) then
						ValueHolder:SetTooltip(
							Locale:GetPhrase( TranslationSource, Setting.Tooltip )
						)
					end

					if Setting.ConfigKey or IsType( Setting.ConfigOption, "string" ) then
						local Key = Setting.ConfigKey or Setting.ConfigOption
						ElementsByKey[ Key ] = {
							ConfigOption = Setting.ConfigOption,
							Command = Setting.Command,
							ValueHolder = ValueHolder,
							Container = Object,
							Update = Creator.Update
						}
						Object:SetDebugName( StringFormat( "ClientConfigMenu%s%sContainer", Key, Setting.Type ) )
						ValueHolder:SetDebugName( StringFormat( "ClientConfigMenu%s%s", Key, Setting.Type ) )
					end

					if Setting.Bindings then
						SettingsWithBindings[ #SettingsWithBindings + 1 ] = Setting
					end

					TabLayout:AddElement( Object )

					if Setting.HelpText then
						local Hint = TabPanel:Add( "Hint" )
						Hint:SetStyleName( Setting.HelpTextStyle or "Info" )
						Hint:SetMargin( Spacing( 0, SMALL_PADDING, 0, i == #Settings and 0 or SMALL_PADDING ) )
						Hint:SetText( Locale:GetPhrase( TranslationSource, Setting.HelpText ) )
						Hint:SetFontScale( GetSmallFont() )

						Hint:SetAutoSize( UnitVector(
							Percentage.ONE_HUNDRED,
							Units.Auto.INSTANCE
						) )

						TabLayout:AddElement( Hint )
					elseif i ~= #Settings then
						Object:SetMargin( Spacing( 0, 0, 0, SMALL_PADDING ) )
					end

					if IsType( Setting.Margin, "table" ) then
						local Margin = Object:GetMargin() or Spacing( 0, 0, 0, 0 )
						for i = 1, 4 do
							if Setting.Margin[ i ] then
								Margin[ i ] = Setting.Margin[ i ]
							end
						end
						Object:SetMargin( Margin )
					end
				end

				for i = 1, #SettingsWithBindings do
					local Setting = SettingsWithBindings[ i ]
					local Bindings = Setting.Bindings

					for j = 1, #Bindings do
						local Binding = Bindings[ j ]
						local From = Binding.From
						local To = Binding.To

						local Builder = Binder()
						Builder:WithReducer( Binding.Reducer )
						Builder:WithInitialState( Binding.InitialState )
						Builder:ToElement(
							ElementsByKey[ Setting.ConfigKey ][ To.Element or "ValueHolder" ], To.Property, To
						)

						if #From == 0 then
							Builder:FromElement( ElementsByKey[ From.Element ].ValueHolder, From.Property )
							Builder:BindProperty()
						else
							for k = 1, #From do
								Builder:FromElement(
									ElementsByKey[ From[ k ].Element ].ValueHolder, From[ k ].Property
								)
							end
							Builder:BindProperties()
						end
					end
				end

				-- Update the UI elements if the setting is changed elsewhere (e.g. running a console command directly).
				Shine.Hook.Add( "OnPluginClientSettingChanged", ConfigMenu, function( Plugin, Setting, NewValue )
					local Element = ElementsByKey[ Setting.ConfigKey ]
					if not Element or Element.Command ~= Setting.Command or not SGUI.IsValid( Element.ValueHolder ) then
						return
					end

					if Setting.Inverted then
						NewValue = not NewValue
					end

					Element.Update( Element.ValueHolder, NewValue )
				end )

				Shine.Hook.Add( "OnClientSettingChanged", ConfigMenu, function( ConfigOption, NewValue )
					local Element = ElementsByKey[ ConfigOption ]
					if
						not Element
						or Element.ConfigOption ~= ConfigOption
						or not SGUI.IsValid( Element.ValueHolder )
					then
						return
					end

					Element.Update( Element.ValueHolder, NewValue )
				end )

				Shine.Hook.Add( "OnConfigMenuVisibilityChanged", ConfigMenu, function( ConfigMenu, Visible )
					if Visible then return end

					-- Immediately close any dropdown menus that are open to avoid them being left on screen briefly
					-- during the close animation.
					for i = 1, #Dropdowns do
						local Dropdown = Dropdowns[ i ]
						if SGUI.IsValid( Dropdown ) then
							Dropdown:DestroyMenu()
						end
					end
				end )

				TabPanel:SetLayout( TabLayout, true )
			end, GroupDef and GroupDef.Icon )

			TabWidth:AddValue( Units.Auto( Tab.TabButton ) + HighResScaled( 16 ) )

			if Data and Data.ActiveTabName == Group then
				Tabs:SetSelectedTab( Tab )
			end
		end

		Layout:AddElement( Tabs )

		Panel:SetLayout( Layout )
	end,

	OnCleanup = function( Panel )
		Shine.Hook.Remove( "OnPluginClientSettingChanged", ConfigMenu )
		Shine.Hook.Remove( "OnClientSettingChanged", ConfigMenu )
		Shine.Hook.Remove( "OnConfigMenuVisibilityChanged", ConfigMenu )

		local Tabs = Panel.SettingsTabs
		Panel.SettingsTabs = nil
		ConfigMenu.SettingsTabs = nil

		if SGUI.IsValid( Tabs ) then
			return {
				ActiveTabName = Tabs:GetActiveTab().Name
			}
		end
	end
} )

do
	local AgencyFBNormal = {
		Family = "kAgencyFB",
		Size = HighResScaled( 27 )
	}
	local AgencyFBMedium = {
		Family = "kAgencyFB",
		Size = Units.HighResScaled( 33 )
	}
	local Ionicons = {
		Family = SGUI.FontFamilies.Ionicons,
		Size = HighResScaled( 27 )
	}

	local TableInsert = table.insert
	local TableSort = table.sort

	local PluginEntry = SGUI:DefineControl( "PluginEntry", "Row" )

	SGUI.AddBoundProperty( PluginEntry, "Active", "EnableSwitch" )

	function PluginEntry:SetPlugin( PluginName )
		local IsOfficial = Shine.IsOfficialExtension( PluginName )
		local Enabled, PluginTable = Shine:IsExtensionEnabled( PluginName )

		local NiceName = Locale:GetPhrase( PluginName, "CLIENT_PLUGIN_NAME" )
		if NiceName == "CLIENT_PLUGIN_NAME" then
			NiceName = PluginName
		end
		local TitleRow = {
			{
				Class = "Label",
				Props = {
					AutoFont = AgencyFBNormal,
					Text = NiceName
				}
			}
		}
		if IsOfficial then
			TitleRow[ 2 ] = {
				Class = "Label",
				Props = {
					AutoFont = Ionicons,
					Margin = Spacing( HighResScaled( 8 ), 0, 0, 0 ),
					StyleName = "InfoLabel",
					Text = SGUI.Icons.Ionicons.AndroidCheckmarkCircle,
					Tooltip = Locale:GetPhrase( "Core", "OFFICIAL_PLUGIN_TOOLTIP" )
				}
			}
		end

		local PluginMetadata = {
			{
				Class = "Horizontal",
				Type = "Layout",
				Props = {
					AutoSize = UnitVector( Units.Auto.INSTANCE, Units.Auto.INSTANCE ),
					Fill = false
				},
				Children = TitleRow
			}
		}

		if PluginTable and PluginTable.Version then
			PluginMetadata[ #PluginMetadata + 1 ] = {
				Class = "Label",
				Props = {
					AutoFont = AgencyFBNormal,
					Margin = Spacing( 0, HighResScaled( 4 ), 0, 0 ),
					Text = Locale:GetInterpolatedPhrase( "Core", "PLUGIN_VERSION", {
						Version = PluginTable.Version
					} )
				}
			}
		end

		local Description = Locale:GetPhrase( PluginName, "CLIENT_PLUGIN_DESCRIPTION" )
		if Description ~= "CLIENT_PLUGIN_DESCRIPTION" then
			PluginMetadata[ #PluginMetadata + 1 ] = {
				Class = "Label",
				Props = {
					AutoFont = AgencyFBNormal,
					AutoSize = UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ),
					AutoWrap = true,
					Margin = Spacing( 0, HighResScaled( 4 ), 0, 0 ),
					Text = Description
				}
			}
		end

		local Elements = SGUI:BuildTree( {
			Parent = self,
			{
				Class = "Vertical",
				Type = "Layout",
				Props = {
					AutoSize = UnitVector( 0, Units.Auto.INSTANCE ),
					Fill = true
				},
				Children = PluginMetadata
			},
			{
				ID = "EnableSwitch",
				Class = "Switch",
				Props = {
					Alignment = SGUI.LayoutAlignment.MAX,
					AutoSize = UnitVector( HighResScaled( 64 ), HighResScaled( 32 ) ),
					CrossAxisAlignment = SGUI.LayoutAlignment.CENTRE,
					Margin = Spacing( HighResScaled( 8 ), 0, 0, 0 )
				},
				Bindings = {
					{
						From = {
							Element = "EnableSwitch",
							Property = "Active"
						},
						To = {
							Property = "Tooltip",
							Transformer = function( Active )
								return Locale:GetPhrase( "Core", Active and "DISABLE_PLUGIN" or "ENABLE_PLUGIN" )
							end
						}
					}
				}
			}
		} )

		local EnableSwitch = Elements.EnableSwitch
		EnableSwitch:SetActive( Enabled, true )

		function EnableSwitch:OnToggled( Active )
			Shared.ConsoleCommand( ( Active and "sh_loadplugin_cl " or "sh_unloadplugin_cl " )..PluginName )
		end

		self.EnableSwitch = EnableSwitch

		self:SetColour( Colour( 0, 0, 0, 0.15 ) )
		self:SetPadding( Spacing( SMALL_PADDING, SMALL_PADDING, SMALL_PADDING, SMALL_PADDING ) )
	end

	local function SortByID( A, B )
		return A.ID < B.ID
	end

	ConfigMenu:AddTab( Locale:GetPhrase( "Core", "PLUGINS_TAB" ), {
		Icon = SGUI.Icons.Ionicons.Settings,
		OnInit = function( Panel )
			local Rows = {}

			for Plugin in pairs( Shine.AllPlugins ) do
				local Enabled, PluginTable = Shine:IsExtensionEnabled( Plugin )

				if PluginTable and PluginTable.IsClient and not PluginTable.IsShared then
					Rows[ #Rows + 1 ] = {
						ID = Plugin,
						Class = PluginEntry,
						Props = {
							Plugin = Plugin,
							Margin = Spacing( 0, 0, 0, SMALL_PADDING ),
							AutoSize = UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE )
						}
					}
				end
			end

			TableSort( Rows, SortByID )

			local LastRow = Rows[ #Rows ]
			if LastRow then
				LastRow.Props.Margin = nil
			end

			local Elements = SGUI:BuildTree( {
				Parent = Panel,
				{
					Class = "Vertical",
					Type = "Layout",
					Props = {
						Padding = Spacing( SMALL_PADDING, SMALL_PADDING, SMALL_PADDING, SMALL_PADDING )
					},
					Children = {
						{
							Class = "Label",
							Props = {
								AutoFont = AgencyFBMedium,
								Text = Locale:GetPhrase( "Core", "CLIENT_PLUGINS" ),
								Margin = Spacing( 0, 0, 0, SMALL_PADDING )
							}
						},
						{
							Class = "Column",
							Props = {
								Scrollable = true,
								Fill = true,
								Colour = Colour( 0, 0, 0, 0 ),
								ScrollbarPos = Vector2( 0, 0 ),
								ScrollbarWidth = HighResScaled( 8 ):GetValue(),
								ScrollbarHeightOffset = 0
							},
							Children = Rows
						}
					}
				}
			} )

			local function UpdateRow( Name, Enabled )
				local Row = Elements[ Name ]
				if SGUI.IsValid( Row ) then
					Row:SetActive( Enabled )
				end
			end

			Shine.Hook.Add( "OnPluginLoad", ConfigMenu, function( Name, Plugin, Shared )
				if not Plugin.IsClient then return end

				UpdateRow( Name, true )
			end )

			Shine.Hook.Add( "OnPluginUnload", ConfigMenu, function( Name, Plugin, Shared )
				if not Plugin.IsClient then return end

				UpdateRow( Name, false )
			end )
		end,

		OnCleanup = function( Panel )
			Shine.Hook.Remove( "OnPluginLoad", ConfigMenu )
			Shine.Hook.Remove( "OnPluginUnload", ConfigMenu )
		end
	} )
end

Shine:RegisterClientCommand( "sh_clientconfigmenu", function()
	ConfigMenu:Show()
end )

-- Add a dummy entry into the game's mod options list with a button to open the config menu.
Shine.Hook.CallAfterFileLoad( "lua/menu2/NavBar/Screens/Options/Mods/ModsMenuData.lua", function()
	if not gModsCategories then return end

	gModsCategories[ #gModsCategories + 1 ] = {
		categoryName = "Shine",
		entryConfig = {
			name = "ShineModEntry",
			class = GUIMenuCategoryDisplayBoxEntry,
			params = {
				label = Shine.Locale:GetPhrase( "Core", "NS2_MENU_OPTIONS_TITLE" )
			}
		},
		contentsConfig = ModsMenuUtils.CreateBasicModsMenuContents( {
			layoutName = "ShineOptions",
			contents = {
				{
					name = "ShineOpenClientConfigMenu",
					class = GUIMenuButton,
					properties = {
						{ "Label", Shine.Locale:GetPhrase( "Core", "NS2_MENU_OPEN_CLIENT_CONFIG" ) }
					},
					postInit = {
						function( self )
							self:HookEvent( self, "OnPressed", function()
								local MainMenu = GetMainMenu and GetMainMenu()
								if MainMenu and MainMenu.Close then
									MainMenu:Close()
								end

								ConfigMenu:Show()
							end )
						end
					}
				}
			}
		} )
	}
end )
