--[[
	Clientside configuration menu.
]]

local SGUI = Shine.GUI

local IsType = Shine.IsType

local ConfigMenu = {}

ConfigMenu.Tabs = {}

local Units = SGUI.Layout.Units
local HighResScaled = Units.HighResScaled
local Percentage = Units.Percentage
local Spacing = Units.Spacing
local UnitVector = Units.UnitVector

ConfigMenu.Size = UnitVector( HighResScaled( 600 ), HighResScaled( 500 ) )
ConfigMenu.EasingTime = 0.25

local function NeedsToScale()
	return SGUI.GetScreenSize() > 1920
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

	local Font, Scale = GetSmallFont()
	self.Menu:SetFont( Font )
	if Scale then
		self.Menu:SetTextScale( Scale )
	end

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
	if NeedsToScale() then
		local Font, Scale = SGUI.FontManager.GetFont( "kArial", 20 )
		self.Menu.CloseButton:SetFont( Font )
		self.Menu.CloseButton:SetTextScale( Scale )
	end
	self.Menu.OnClose = function()
		self:SetIsVisible( false )
		return true
	end
end

Shine.Hook.Add( "OnResolutionChanged", "ClientConfig_OnResolutionChanged", function()
	if not ConfigMenu.Menu then return end

	ConfigMenu.Menu:Destroy()
	ConfigMenu.Menu = nil

	if ConfigMenu.Visible then
		ConfigMenu:Create()
	end
end )

function ConfigMenu:SetIsVisible( Bool )
	if self.Visible == Bool then return end

	if not self.Menu then
		self:Create()
	end

	Shine.AdminMenu.AnimateVisibility( self.Menu, Bool, self.Visible, self.EasingTime, self.Pos )
	self.Visible = Bool
end

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

local SettingsTypes = {
	Boolean = {
		Create = function( Panel, Entry )
			local CheckBox = Panel:Add( "CheckBox" )
			local Font, Scale = GetSmallFont()
			CheckBox:SetFont( Font )
			if Scale then
				CheckBox:SetTextScale( Scale )
			end
			CheckBox:AddLabel( Entry.Description )
			CheckBox:SetAutoSize( UnitVector( HighResScaled( 24 ), HighResScaled( 24 ) ) )

			local Enabled
			if IsType( Entry.ConfigOption, "string" ) then
				Enabled = Shine.Config[ Entry.ConfigOption ]
			else
				Enabled = Entry.ConfigOption()
			end

			CheckBox:SetChecked( Enabled or false, true )
			CheckBox.OnChecked = function( CheckBox, Value )
				Shared.ConsoleCommand( Entry.Command.." "..tostring( Value ) )
			end

			return CheckBox
		end
	}
}

ConfigMenu:AddTab( "Settings", {
	OnInit = function( Panel )
		Panel:SetScrollable()

		local Settings = Shine.ClientSettings
		local Layout = SGUI.Layout:CreateLayout( "Vertical", {
			Padding = Spacing( HighResScaled( 24 ), HighResScaled( 32 ),
				HighResScaled( 24 ), HighResScaled( 32 ) )
		} )

		local Title = Panel:Add( "Label" )
		local Font, Scale = GetMediumFont()
		Title:SetFont( Font )
		if Scale then
			Title:SetTextScale( Scale )
		end
		Title:SetText( "Client Settings" )
		Title:SetMargin( Spacing( 0, 0, 0, HighResScaled( 16 ) ) )
		Title:SetBright( true )
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
		List:SetColumns( 2, "Plugin", "State" )
		List:SetSpacing( 0.7, 0.3 )
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
		EnableButton:SetText( "Enable Plugin" )
		EnableButton:SetFont( Font )
		if Scale then
			EnableButton:SetTextScale( Scale )
		end

		Layout:AddElement( EnableButton )

		function EnableButton:DoClick()
			local Selected = List:GetSelectedRow()
			if not Selected then return end

			local Plugin = Selected:GetColumnText( 1 )
			local Enabled = Selected:GetColumnText( 2 ) == "Enabled"

			Shared.ConsoleCommand( ( Enabled and "sh_unloadplugin_cl " or "sh_loadplugin_cl " )..Plugin )
		end

		function List:OnRowSelected( Index, Row )
			local State = Row:GetColumnText( 2 )

			if State == "Enabled" then
				EnableButton:SetText( "Disable Plugin" )
			else
				EnableButton:SetText( "Enable Plugin" )
			end
		end

		local Rows = {}

		local function UpdateRow( Name, Text )
			local Row = Rows[ Name ]
			if not Row then return end

			Row:SetColumnText( 2, Text )
			if Row == List:GetSelectedRow() then
				List:OnRowSelected( nil, Row )
			end
		end

		Shine.Hook.Add( "OnPluginLoad", "ClientConfig_OnPluginLoad", function( Name, Plugin, Shared )
			if not Plugin.IsClient then return end

			UpdateRow( Name, "Enabled" )
		end )

		Shine.Hook.Add( "OnPluginUnload", "ClientConfig_OnPluginUnload", function( Name, Plugin, Shared )
			if not Plugin.IsClient then return end

			UpdateRow( Name, "Disabled" )
		end )

		Panel:SetLayout( Layout )

		for Plugin in pairs( Shine.AllPlugins ) do
			local Enabled, PluginTable = Shine:IsExtensionEnabled( Plugin )

			if PluginTable and PluginTable.IsClient and not PluginTable.IsShared then
				Rows[ Plugin ] = List:AddRow( Plugin, Enabled and "Enabled" or "Disabled" )
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
	ConfigMenu:SetIsVisible( true )
end )
