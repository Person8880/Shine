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

Shine:RegisterCommand( "sh_setloglevel", nil, function( Client, PluginName, LogLevel )
	local Plugin = Shine.Plugins[ PluginName ]
	if not Plugin then
		Shine:NotifyCommandError( Client, "No plugin named '%s' exists.", true, PluginName )
		return
	end

	if not Plugin.Logger then
		Shine:NotifyCommandError( Client, "Plugin '%s' has no logger to configure.", true, PluginName )
		return
	end

	local ValidLevels = Shine.Objects.Logger.LogLevel
	LogLevel = StringUpper( LogLevel )

	if not ValidLevels[ LogLevel ] then
		Shine:NotifyCommandError( Client, "Invalid log level: '%s'. Expected one of %s.", true,
			LogLevel, TableConcat( ValidLevels, ", " ) )
		return
	end

	Plugin.Logger:SetLevel( LogLevel )
	Plugin.Config.LogLevel = LogLevel
	Plugin:SaveConfig()

	Shine:AdminPrint( Client, "Log level of plugin '%s' set to '%s'.", true, PluginName, LogLevel )
end )
:Help( "Sets the log level for the given plugin." )
:AddParam( {
	Type = "string", Help = "Plugin Name"
} )
:AddParam( {
	Type = "string", Help = "Log Level"
} )

Plugin:AddModule( Module )
