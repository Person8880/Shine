--[[
	Clientside configuration menu.
]]

local SGUI = Shine.GUI
local Locale = Shine.Locale

local IsType = Shine.IsType

local ConfigMenu = {}
SGUI:AddMixin( ConfigMenu, "Visibility" )

ConfigMenu.Tabs = {}

local Units = SGUI.Layout.Units
local HighResScaled = Units.HighResScaled
local Percentage = Units.Percentage
local Spacing = Units.Spacing
local UnitVector = Units.UnitVector

ConfigMenu.Size = UnitVector( HighResScaled( 700 ), HighResScaled( 500 ) )
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
	self.Menu:SetAnchor( "CentreMiddle" )
	self.Menu:SetAutoSize( self.Size, true )

	self.Menu:SetTabWidth( HighResScaled( 128 ):GetValue() )
	self.Menu:SetTabHeight( HighResScaled( 96 ):GetValue() )
	self.Menu:SetFontScale( GetSmallFont() )

	self.Pos = self.Menu:GetSize() * -0.5
	self.Menu:SetPos( self.Pos )

	self.Menu.OnPreTabChange = function( Window )
		if not Window.ActiveTab then return end

		local Tab = self.Tabs[ Window.ActiveTab ]
		if not Tab or not Tab.OnCleanup then return end

		Tab.OnCleanup( Window.ContentPanel )
	end

	self.Menu.TitleBarHeight = HighResScaled( 24 ):GetValue()
	self:PopulateTabs( self.Menu )

	self.Menu:AddCloseButton()
	self.Menu.OnClose = function()
		self:ForceHide()
		return true
	end
end

function ConfigMenu:Close()
	if not self.Menu or not self.Visible then return end

	self.Menu:Close()
end

Shine.Hook.Add( "OnResolutionChanged", "ClientConfig_OnResolutionChanged", function()
	if not ConfigMenu.Menu then return end

	ConfigMenu.Menu:Destroy()
	ConfigMenu.Menu = nil

	if ConfigMenu.Visible then
		ConfigMenu:Create()
	end
end )

Shine.Hook.Add( "PlayerKeyPress", "ConfigMenu_KeyPress", function( Key, Down )
	return Shine.AdminMenu.PlayerKeyPress( ConfigMenu, Key, Down )
end, 1 )

-- Close when logging in/out of a command structure to avoid mouse problems.
Shine.Hook.Add( "OnCommanderLogout", "ConfigMenuLogout", function()
	ConfigMenu:Close()
end )
Shine.Hook.Add( "OnCommanderLogin", "ConfigMenuLogin", function()
	ConfigMenu:Close()
end )

function ConfigMenu:SetIsVisible( Bool, IgnoreAnim )
	if self.Visible == Bool then return end

	if not self.Menu then
		self:Create()
	end

	Shine.AdminMenu.AnimateVisibility( self.Menu, Bool, self.Visible, self.EasingTime, self.Pos, IgnoreAnim )

	self.Visible = Bool
end

function ConfigMenu:GetIsVisible()
	return self.Visible or false
end

ConfigMenu:BindVisibilityToEvents( "OnHelpScreenDisplay", "OnHelpScreenHide" )

function ConfigMenu:PopulateTabs( Menu )
	local Tabs = self.Tabs
	for i = 1, #Tabs do
		local Tab = Tabs[ i ]
		Menu:AddTab( Tab.Name, function( Panel )
			Tab.OnInit( Panel )
		end )
	end
end

function ConfigMenu:AddTab( Name, Tab )
	if self.Tabs[ Name ] then return end

	Tab.Name = Name
	self.Tabs[ Name ] = Tab
	self.Tabs[ #self.Tabs + 1 ] = Tab
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

local SettingsTypes = {
	Boolean = {
		Create = function( Panel, Entry )
			local CheckBox = Panel:Add( "CheckBox" )
			CheckBox:SetFontScale( GetSmallFont() )
			CheckBox:AddLabel( Locale:GetPhrase( Entry.TranslationSource or "Core", Entry.Description ) )
			CheckBox:SetAutoSize( UnitVector( HighResScaled( 24 ), HighResScaled( 24 ) ) )

			local Enabled = GetConfiguredValue( Entry )

			CheckBox:SetChecked( Enabled or false, true )
			CheckBox.OnChecked = function( CheckBox, Value )
				Shared.ConsoleCommand( Entry.Command.." "..tostring( Value ) )
			end

			return CheckBox
		end
	},
	Radio = {
		Create = function( Panel, Entry )
			local RadioPanel = Panel:Add( "Panel" )
			RadioPanel:SetAutoSize( UnitVector( Percentage( 100 ), HighResScaled( 56 ) ) )

			local TranslationSource = Entry.TranslationSource or "Core"

			local VerticalLayout = SGUI.Layout:CreateLayout( "Vertical", {} )
			local Description = RadioPanel:Add( "Label" )
			Description:SetFontScale( GetSmallFont() )
			Description:SetText( Locale:GetPhrase( TranslationSource, Entry.Description ) )
			Description:SetAutoSize( UnitVector( Percentage( 100 ), HighResScaled( 24 ) ) )
			Description:SetMargin( Spacing( 0, 0, 0, HighResScaled( 8 ) ) )
			VerticalLayout:AddElement( Description )

			local RadioLayout = SGUI.Layout:CreateLayout( "Horizontal", {} )

			local CheckBoxes = {}
			local CurrentChoice = GetConfiguredValue( Entry )
			local PercentPerCheckbox = 100 / #Entry.Options
			for i = 1, #Entry.Options do
				local Option = Entry.Options[ i ]

				local CheckBox = RadioPanel:Add( "CheckBox" )
				CheckBox:SetFontScale( GetSmallFont() )
				CheckBox:AddLabel( Locale:GetPhrase( TranslationSource, Option ) )
				CheckBox:SetAutoSize( UnitVector( HighResScaled( 24 ), HighResScaled( 24 ) ) )
				if i > 1 then
					CheckBox:SetMargin( Spacing( Percentage( PercentPerCheckbox ), 0, 0, 0 ) )
				end
				CheckBox:SetRadio( true )

				CheckBox:SetChecked( CurrentChoice == Option )
				CheckBox.OnChecked = function( CheckBox, Value )
					if not Value then return end

					Shared.ConsoleCommand( Entry.Command.." "..Option )
					for j = 1, #CheckBoxes do
						if CheckBoxes[ j ] ~= CheckBox then
							CheckBoxes[ j ]:SetChecked( false )
						end
					end
				end

				RadioLayout:AddElement( CheckBox )
				CheckBoxes[ #CheckBoxes + 1 ] = CheckBox
			end

			VerticalLayout:AddElement( RadioLayout )
			RadioPanel:SetLayout( VerticalLayout )

			return RadioPanel
		end
	}
}

ConfigMenu:AddTab( "Settings", {
	OnInit = function( Panel )
		Panel:SetScrollable()
		Panel:SetScrollbarHeightOffset( HighResScaled( 40 ):GetValue() )
		Panel:SetScrollbarWidth( HighResScaled( 8 ):GetValue() )
		Panel:SetScrollbarPos( Vector2( -HighResScaled( 16 ):GetValue(), HighResScaled( 32 ):GetValue() ) )

		local Settings = Shine.ClientSettings
		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Spacing( HighResScaled( 24 ), HighResScaled( 32 ),
				HighResScaled( 24 ), HighResScaled( 32 ) )
		} )

		local Title = Panel:Add( "Label" )
		Title:SetFontScale( GetMediumFont() )
		Title:SetText( Locale:GetPhrase( "Core", "CLIENT_SETTINGS" ) )
		Title:SetMargin( Spacing( 0, 0, 0, HighResScaled( 16 ) ) )
		Layout:AddElement( Title )

		for i = 1, #Settings do
			local Setting = Settings[ i ]
			local Creator = SettingsTypes[ Setting.Type ]

			if Creator then
				local Object = Creator.Create( Panel, Setting )
				Object:SetMargin( Spacing( 0, 0, 0, HighResScaled( 8 ) ) )
				Layout:AddElement( Object )
			end
		end

		Panel:SetLayout( Layout )
	end
} )

ConfigMenu:AddTab( "Plugins", {
	OnInit = function( Panel )
		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Spacing( HighResScaled( 16 ), HighResScaled( 32 ),
				HighResScaled( 16 ), HighResScaled( 16 ) )
		} )

		local List = SGUI:Create( "List", Panel )
		List:SetColumns( Locale:GetPhrase( "Core", "PLUGIN" ),
			Locale:GetPhrase( "Core", "STATE" ) )
		List:SetSpacing( 0.8, 0.2 )
		List.ScrollPos = Vector2( 0, 32 )
		List:SetFill( true )
		List:SetMargin( Spacing( 0, 0, 0, HighResScaled( 8 ) ) )
		List:SetLineSize( HighResScaled( 32 ):GetValue() )
		List:SetHeaderSize( List.LineSize )

		local Font, Scale = GetSmallFont()
		List:SetHeaderFont( Font )
		List:SetRowFont( Font )
		if Scale then
			List:SetHeaderTextScale( Scale )
			List:SetRowTextScale( Scale )
		end

		Layout:AddElement( List )

		local EnableButton = SGUI:Create( "Button", Panel )
		EnableButton:SetAutoSize( UnitVector( Percentage( 100 ), HighResScaled( 32 ) ) )
		EnableButton:SetText( Locale:GetPhrase( "Core", "ENABLE_PLUGIN" ) )
		EnableButton:SetFontScale( Font, Scale )
		EnableButton:SetEnabled( false )

		Layout:AddElement( EnableButton )

		function EnableButton:DoClick()
			local Selected = List:GetSelectedRow()
			if not Selected then return end

			local Plugin = Selected:GetColumnText( 1 )
			local Enabled = Selected.PluginEnabled

			Shared.ConsoleCommand( ( Enabled and "sh_unloadplugin_cl " or "sh_loadplugin_cl " )..Plugin )
		end

		function List:OnRowSelected( Index, Row )
			local State = Row.PluginEnabled

			EnableButton:SetEnabled( true )
			if State then
				EnableButton:SetText( Locale:GetPhrase( "Core", "DISABLE_PLUGIN" ) )
				EnableButton:SetStyleName( "DangerButton" )
			else
				EnableButton:SetText( Locale:GetPhrase( "Core", "ENABLE_PLUGIN" ) )
				EnableButton:SetStyleName( "SuccessButton" )
			end
		end

		function List:OnRowDeselected( Index, Row )
			EnableButton:SetEnabled( false )
		end

		local Rows = {}

		local function UpdateRow( Name, State )
			local Row = Rows[ Name ]
			if not Row then return end

			local Font, Scale = SGUI.FontManager.GetHighResFont( SGUI.FontFamilies.Ionicons, 27 )
			Row:SetColumnText( 2, SGUI.Icons.Ionicons[ State and "CheckmarkCircled" or "MinusCircled" ] )
			Row:SetTextOverride( 2, {
				Font = Font,
				TextScale = Scale,
				Colour = State and Colour( 0, 1, 0 ) or Colour( 1, 0.8, 0 )
			} )
			Row:SetData( 2, State and "1" or "0" )
			Row.PluginEnabled = State

			if Row == List:GetSelectedRow() then
				List:OnRowSelected( nil, Row )
			end
		end

		Shine.Hook.Add( "OnPluginLoad", "ClientConfig_OnPluginLoad", function( Name, Plugin, Shared )
			if not Plugin.IsClient then return end

			UpdateRow( Name, true )
		end )

		Shine.Hook.Add( "OnPluginUnload", "ClientConfig_OnPluginUnload", function( Name, Plugin, Shared )
			if not Plugin.IsClient then return end

			UpdateRow( Name, false )
		end )

		Panel:SetLayout( Layout )

		for Plugin in pairs( Shine.AllPlugins ) do
			local Enabled, PluginTable = Shine:IsExtensionEnabled( Plugin )

			if PluginTable and PluginTable.IsClient and not PluginTable.IsShared then
				local Row = List:AddRow( Plugin, "" )
				Rows[ Plugin ] = Row
				UpdateRow( Plugin, Enabled )
			end
		end

		List:SortRows( 1 )
	end,

	OnCleanup = function( Panel )
		Shine.Hook.Remove( "OnPluginLoad", "ClientConfig_OnPluginLoad" )
		Shine.Hook.Remove( "OnPluginUnload", "ClientConfig_OnPluginUnload" )
	end
} )

Shine:RegisterClientCommand( "sh_clientconfigmenu", function()
	ConfigMenu:Show()
end )
