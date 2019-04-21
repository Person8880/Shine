--[[
	Client side configuration.
]]

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
	ExpandConfigMenuTabs = true
}

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

	if self.CheckConfig( self.Config, DefaultConfig ) then
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

	if CurrentValue == Value then return end

	self.Config[ Key ] = Value
	self:SaveClientBaseConfig()
end

Shine:LoadClientBaseConfig()

local function MakeClientOption( Command, OptionKey, OptionString, Yes, No )
	local ConCommand = Shine:RegisterClientCommand( Command, function( Bool )
		Shine.Config[ OptionKey ] = Bool

		Notify( StringFormat( "[Shine] %s %s.", OptionString, Bool and Yes or No ) )

		Shine:SaveClientBaseConfig()
	end )
	ConCommand:AddParam{ Type = "boolean", Optional = true,
		Default = function() return not Shine.Config[ OptionKey ] end }
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
		Message = "Shine is set to display web pages from plugins. If you wish to globally disable web page display, then enter \"sh_disableweb 1\" into the console."
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
		Message = "Shine is set to display web pages in the Steam overlay. If you wish to show them using the in game browser, then enter \"sh_viewwebinsteam 0\" into the console."
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
		Message = "Shine is set to report any errors it causes on your client when you disconnect. If you do not wish it to do so, then enter \"sh_errorreport 0\" into the console."
	},
	{
		Type = "Boolean",
		Command = "sh_animateui",
		Description = "ANIMATE_UI_DESCRIPTION",
		ConfigOption = "AnimateUI",
		Data = {
			"sh_animateui", "AnimateUI",
			"UI animations have been", "enabled", "disabled"
		},
		AlwaysShowMessage = true,
		Message = "You can enable/disable UI animations by entering \"sh_animateui\" into the console."
	}
}
Shine.ClientSettings = Options

do
	local TableFindByField = table.FindByField

	function Shine:RegisterClientSetting( Entry )
		local Existing, Index = TableFindByField( Options, "Command", Entry.Command )
		if Existing then
			Options[ Index ] = Entry
		else
			Options[ #Options + 1 ] = Entry
		end
	end
end

for i = 1, #Options do
	local Option = Options[ i ]

	MakeClientOption( unpack( Option.Data ) )
	if Shine.Config[ Option.Data[ 2 ] ] == Option.MessageState or Option.AlwaysShowMessage then
		Shine.AddStartupMessage( Option.Message )
	end
end

Script.Load( "lua/shine/core/client/config_gui.lua" )
