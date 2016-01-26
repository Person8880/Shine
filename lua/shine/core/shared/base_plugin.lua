--[[
	Base plugin metatable.
]]

local Shine = Shine

local pairs = pairs
local rawget = rawget
local StringFormat = string.format
local TableShallowMerge = table.ShallowMerge

local PluginMeta = {}
Shine.BasePlugin = PluginMeta

-- Modules are static mixins that are applied to the base plugin.
PluginMeta.Modules = {}

--[[
	Base initialise, just enables the plugin, nothing more.
	Override to add to it.
]]
function PluginMeta:Initialise()
	self:CallModuleEvent( "Initialise" )
	self.Enabled = true

	return true
end

--[[
	*STATIC* method to register a module against the base plugin.

	Modules are small self-contained bits of behaviour that are helpful to provide to
	all plugins. They are loaded from core/shared/base_plugin.
]]
function PluginMeta:AddModule( Module )
	self.Modules[ #self.Modules + 1 ] = Module
	TableShallowMerge( Module, self )
end

--[[
	Calls an event on all modules that have a listener for it.
]]
function PluginMeta:CallModuleEvent( Event, ... )
	for i = 1, #self.Modules do
		local Module = self.Modules[ i ]
		if Module[ Event ] then
			Module[ Event ]( self, ... )
		end
	end
end

if Server then
	--[[
		Default cleanup will remove any bound commands.
		Override to add/change behaviour, call it with self.BaseClass.Cleanup( self ).
	]]
	function PluginMeta:Cleanup()
		self:CallModuleEvent( "Cleanup" )
	end
elseif Client then
	function PluginMeta:Cleanup()
		self:CallModuleEvent( "Cleanup" )
	end
end

--[[
	Suspends the plugin, stopping its hooks, pausing its timers, but not calling Cleanup().
]]
function PluginMeta:Suspend()
	if self.OnSuspend then
		self:OnSuspend()
	end

	self:CallModuleEvent( "Suspend" )

	self.Enabled = false
	self.Suspended = true
end

--[[
	Resumes the plugin from suspension.
]]
function PluginMeta:Resume()
	self:CallModuleEvent( "Resume" )

	self.Enabled = true
	self.Suspended = nil

	if self.OnResume then
		self:OnResume()
	end
end

--[[
	Provides an easy way to delay actions in think-esque hooks.
]]
function PluginMeta:CanRunAction( Action, Time, Delay )
	self.TimedActions = rawget( self, "TimedActions" ) or {}

	if ( self.TimedActions[ Action ] or 0 ) > Time then return false end

	self.TimedActions[ Action ] = Time + Delay

	return true
end

--[[
	Wraps a callback so that it is only executed if the plugin is still enabled.
]]
function PluginMeta:WrapCallback( Callback )
	return function( ... )
		if not self.Enabled then return end

		return Callback( ... )
	end
end

local ReservedKeys = {
	Enabled = true,
	Suspended = true
}
function PluginMeta:__index( Key )
	if ReservedKeys[ Key ] then return nil end

	local Inherit = rawget( self, "__Inherit" )
	if Inherit then
		local InheritBlacklist = rawget( self, "__InheritBlacklist" )
		local InheritWhitelist = rawget( self, "__InheritWhitelist" )
		local InheritedValue = Inherit[ Key ]

		if not InheritBlacklist and not InheritWhitelist then
			if InheritedValue ~= nil then
				return InheritedValue
			end
		else
			if InheritBlacklist and InheritBlacklist[ Key ] then return PluginMeta[ Key ] end
			if InheritWhitelist and not InheritWhitelist[ Key ] then return PluginMeta[ Key ] end

			if InheritedValue ~= nil then
				return InheritedValue
			end
		end
	end

	return PluginMeta[ Key ]
end

Shine.LoadScriptsByPath( "lua/shine/core/shared/base_plugin" )
