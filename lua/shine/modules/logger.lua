--[[
	Provides a configurable logger for a plugin.
]]

local Plugin = ... or _G.Plugin

local StringUpper = string.upper
local TableConcat = table.concat

local Module = {}

Module.DefaultConfig = {
	LogLevel = "INFO"
}

do
	local Validator = Shine.Validator()

	Validator:AddFieldRule(
		"LogLevel",
		Validator.InEnum( Shine.Objects.Logger.LogLevel, Module.DefaultConfig.LogLevel )
	)

	Module.ConfigValidator = Validator
end

function Module:Initialise()
	self.Logger = Shine.Objects.Logger( StringUpper( self.Config.LogLevel ), function( Text )
		return self:Print( Text )
	end )
end

local NotifyError
local AdminPrint

if Server then
	NotifyError = function( Client, Message, ... )
		Shine:NotifyCommandError( Client, Message, true, ... )
	end
	AdminPrint = function( Client, Message, ... )
		Shine:AdminPrint( Client, Message, true, ... )
	end
else
	NotifyError = function( Client, Message, ... )
		Print( Message, ... )
	end
	AdminPrint = function( Client, Message, ... )
		Print( Message, ... )
	end
end

local function SetLogLevel( Client, PluginName, LogLevel )
	local Plugin = Shine.Plugins[ PluginName ]
	if not Plugin then
		NotifyError( Client, "No plugin named '%s' exists.", PluginName )
		return
	end

	if not Plugin.Logger or not Shine.Implements( Plugin.Logger, Shine.Objects.Logger ) then
		NotifyError( Client, "Plugin '%s' has no logger to configure.", PluginName )
		return
	end

	local ValidLevels = Shine.Objects.Logger.LogLevel
	LogLevel = StringUpper( LogLevel )

	if not ValidLevels[ LogLevel ] then
		NotifyError( Client, "Invalid log level: '%s'. Expected one of %s.",
			LogLevel, TableConcat( ValidLevels, ", " ) )
		return
	end

	Plugin.Logger:SetLevel( LogLevel )
	Plugin.Config.LogLevel = LogLevel
	Plugin:SaveConfig()

	AdminPrint( Client, "Log level of plugin '%s' set to '%s'.", PluginName, LogLevel )
end

if Server then
	Shine:RegisterCommand( "sh_setloglevel", nil, SetLogLevel )
	:Help( "Sets the log level for the given plugin." )
	:AddParam( {
		Type = "string", Help = "Plugin Name"
	} )
	:AddParam( {
		Type = "string", Help = "Log Level"
	} )
else
	Shine:RegisterClientCommand( "sh_setloglevel_cl", function( PluginName, LogLevel )
		SetLogLevel( nil, PluginName, LogLevel )
	end )
	:AddParam( {
		Type = "string"
	} )
	:AddParam( {
		Type = "string"
	} )
end

Plugin:AddModule( Module )
