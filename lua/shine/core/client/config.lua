--[[
	Client side configuration.
]]

local Hook = Shine.Hook

local Notify = Shared.Message
local StringFormat = string.format

local BaseConfig = "config://shine/cl_config.json"

local DefaultConfig = {
	DisableWebWindows = false,
	ShowWebInSteamBrowser = false,
	ReportErrors = true,
	AnimateUI = true,
	DebugLogging = false,
	ExpandAdminMenuTabs = true,
	ExpandConfigMenuTabs = true,
	Skin = "Default",
	LogLevel = "INFO"
}

local Validator = Shine.Validator()
Validator:AddFieldRule( "LogLevel", Validator.InEnum(
	Shine.Objects.Logger.LogLevel, Shine.Objects.Logger.LogLevel.INFO
) )

function Shine:CreateClientBaseConfig()
	self.SaveJSONFile( DefaultConfig, BaseConfig )
	self.Config = DefaultConfig
end

function Shine:LoadClientBaseConfig()
	local Data, Err = self.LoadJSONFile( BaseConfig )
	if not Data then
		self:CreateClientBaseConfig()
		return
	end

	self.Config = Data

	if self.CheckConfig( self.Config, DefaultConfig ) or Validator:Validate( self.Config ) then
		self:SaveClientBaseConfig()
	end
end

function Shine:SaveClientBaseConfig()
	self.SaveJSONFile( self.Config, BaseConfig )
end

function Shine:SetClientSetting( Key, Value )
	local CurrentValue = self.Config[ Key ]
	Shine.AssertAtLevel( CurrentValue ~= nil, "Unknown config key: %s", 3, Key )
	Shine.TypeCheck( Value, type( CurrentValue ), 2, "SetClientSetting" )

	if CurrentValue == Value then return false end

	self.Config[ Key ] = Value
	self:SaveClientBaseConfig()

	Hook.Broadcast( "OnClientSettingChanged", Key, Value )

	return true
end

Shine:LoadClientBaseConfig()
Shine.Logger:SetLevel( Shine.Config.LogLevel )

local function MakeClientOption( Command, OptionKey, OptionString, Yes, No )
	local ConCommand = Shine:RegisterClientCommand( Command, function( Bool )
		if Shine:SetClientSetting( OptionKey, Bool ) then
			Notify( StringFormat( "[Shine] %s %s.", OptionString, Bool and Yes or No ) )
		end
	end )
	ConCommand:AddParam{
		Type = "boolean",
		Optional = true,
		Default = function() return not Shine.Config[ OptionKey ] end
	}
end

local Options = {
	{
		Type = "Boolean",
		Command = "sh_disableweb",
		Description = "DISABLE_WEB_DESCRIPTION",
		ConfigOption = "DisableWebWindows",
		Data = {
			"sh_disableweb", "DisableWebWindows",
			"Web page display has been", "disabled", "enabled"
		},
		MessageState = false,
		Message = "Shine is set to display web pages from plugins. If you wish to globally disable web page display, then enter \"sh_disableweb 1\" into the console or use the config menu."
	},
	{
		Type = "Boolean",
		Command = "sh_viewwebinsteam",
		Description = "VIEW_WEB_IN_STEAM_DESCRIPTION",
		ConfigOption = "ShowWebInSteamBrowser",
		Data = {
			"sh_viewwebinsteam", "ShowWebInSteamBrowser",
			"Web page display set to", "Steam browser", "in game window"
		},
		MessageState = true,
		Message = "Shine is set to display web pages in the Steam overlay. If you wish to show them using the in game browser, then enter \"sh_viewwebinsteam 0\" into the console or use the config menu."
	},
	{
		Type = "Boolean",
		Command = "sh_errorreport",
		Description = "REPORT_ERRORS_DESCRIPTION",
		ConfigOption = "ReportErrors",
		Data = {
			"sh_errorreport", "ReportErrors",
			"Error reporting has been", "enabled", "disabled"
		},
		MessageState = true,
		Message = "Shine is set to report any errors it causes on your client. If you do not wish it to do so, then enter \"sh_errorreport 0\" into the console or use the config menu."
	},
	{
		Type = "Boolean",
		Command = "sh_animateui",
		Description = "ANIMATE_UI_DESCRIPTION",
		ConfigOption = "AnimateUI",
		Data = {
			"sh_animateui", "AnimateUI",
			"UI animations have been", "enabled", "disabled"
		}
	}
}
Shine.ClientSettings = Options

do
	local TableFindByField = table.FindByField
	local TableRemove = table.remove

	function Shine:RegisterClientSetting( Entry )
		local Existing, Index = TableFindByField( Options, "Command", Entry.Command )
		if Existing then
			Options[ Index ] = Entry
		else
			Options[ #Options + 1 ] = Entry
		end

		Hook.Broadcast( "OnClientSettingAdded", Entry )
	end

	function Shine:RemoveClientSetting( Entry )
		local Existing, Index = TableFindByField( Options, "Command", Entry.Command )
		if Existing then
			TableRemove( Options, Index )

			Hook.Broadcast( "OnClientSettingRemoved", Entry )

			return true
		end

		return false
	end
end

Shine.AddStartupMessage( "You can configure various client-side options using the config menu. To access it, either "..
	"use the sh_clientconfigmenu command in the console, or use the button in the vote menu." )

for i = 1, #Options do
	local Option = Options[ i ]

	MakeClientOption( unpack( Option.Data ) )
	if Shine.Config[ Option.Data[ 2 ] ] == Option.MessageState or Option.AlwaysShowMessage then
		Shine.AddStartupMessage( Option.Message )
	end
end

do
	local SGUI = Shine.GUI
	Shine:RegisterClientCommand( "sh_setskin", function( SkinName )
		local Skins = SGUI.SkinManager:GetSkinsByName()
		if not Skins[ SkinName ] then
			Notify( StringFormat( "%s is not a valid skin name.", SkinName ) )
			return
		end

		if Shine:SetClientSetting( "Skin", SkinName ) then
			SGUI.SkinManager:SetSkin( SkinName )

			Notify( StringFormat( "Default skin changed to: %s.", SkinName ) )
		end
	end ):AddParam{
		Type = "string", TakeRestOfLine = true
	}

	table.insert( Options, 1, {
		Type = "Dropdown",
		Command = "sh_setskin",
		Description = "SKIN_DESCRIPTION",
		ConfigOption = "Skin",
		Options = function()
			local Skins = SGUI.SkinManager:GetSkinsByName()
			local Options = {}

			for Skin in SortedPairs( Skins ) do
				Options[ #Options + 1 ] = {
					Text = Skin,
					Value = Skin
				}
			end

			return Options
		end
	} )
end

Script.Load( "lua/shine/core/client/config_gui.lua" )
