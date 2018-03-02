--[[
	Base plugin metatable.
]]

local Shine = Shine

local rawget = rawget
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
	self:BroadcastModuleEvent( "Initialise" )
	self.Enabled = true

	return true
end

--[[
	Indicates whether the plugin has been previously enabled.
	This assumes the plugin isn't touching its Enabled field before initialisation.
]]
function PluginMeta:IsFirstTimeLoaded()
	return self.Enabled == nil
end

--[[
	*STATIC* method to register a module against the plugin.

	Modules are small self-contained bits of behaviour that split up distinct pieces of functionality
	in a plugin.

	The base plugin loads its modules from core/shared/base_plugin. Plugin instances receive
	a copy of their parent's modules, which they can then add to.
]]
function PluginMeta:AddModule( Module )
	self.Modules[ #self.Modules + 1 ] = Module
	TableShallowMerge( Module, self )

	-- Merge configuration values if provided.
	if Module.DefaultConfig and self.DefaultConfig ~= Module.DefaultConfig then
		TableShallowMerge( Module.DefaultConfig, self.DefaultConfig )
	end

	-- Merge any configuration validation rules.
	if Module.ConfigValidator and self.ConfigValidator
	and self.ConfigValidator ~= Module.ConfigValidator then
		self.ConfigValidator:Add( Module.ConfigValidator )
	end
end

--[[
	Internal function, do not call!

	Sets up the event dispatcher for sending events to plugin modules.
]]
function PluginMeta:SetupDispatcher()
	self.EventDispatcher = Shine.EventDispatcher( self.Modules )

	local Plugin = self
	-- Call module events with self being the plugin.
	function self.EventDispatcher:CallEvent( Module, Method, ... )
		return Method( Plugin, ... )
	end
end

--[[
	Calls an event on all modules that have a listener for it,
	returning the values from the first module to return a value.
]]
function PluginMeta:CallModuleEvent( Event, ... )
	return self.EventDispatcher:DispatchEvent( Event, ... )
end

--[[
	Calls an event on all modules that have a listener for it
	without stopping if a module returns a value.
]]
function PluginMeta:BroadcastModuleEvent( Event, ... )
	self.EventDispatcher:BroadcastEvent( Event, ... )
end

--[[
	Default cleanup will remove any bound commands.
	Override to add/change behaviour, call it with self.BaseClass.Cleanup( self ).
]]
function PluginMeta:Cleanup()
	self:BroadcastModuleEvent( "Cleanup" )
end

--[[
	Suspends the plugin, stopping its hooks, pausing its timers, but not calling Cleanup().
]]
function PluginMeta:Suspend()
	if self.OnSuspend then
		self:OnSuspend()
	end

	self:BroadcastModuleEvent( "Suspend" )

	self.Enabled = false
	self.Suspended = true
end

--[[
	Resumes the plugin from suspension.
]]
function PluginMeta:Resume()
	self:BroadcastModuleEvent( "Resume" )

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

do
	local ErrorHandler = Shine.BuildErrorHandler( "Plugin callback error" )
	local xpcall = xpcall

	local function UnwrapResults( Success, ... )
		if not Success then
			return nil
		end
		return ...
	end

	--[[
		Wraps a callback so that it is only executed if the plugin is still enabled.
	]]
	function PluginMeta:WrapCallback( Callback )
		return function( ... )
			if not self.Enabled then return end

			return UnwrapResults( xpcall( Callback, ErrorHandler, ... ) )
		end
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
