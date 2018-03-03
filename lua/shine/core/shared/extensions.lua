--[[
	Shine extension system.

	Supports server side, client side and shared plugins.
]]

local Shine = Shine

local include = Script.Load
local IsType = Shine.IsType
local next = next
local pairs = pairs
local Notify = Shared.Message
local pcall = pcall
local setmetatable = setmetatable
local StringExplode = string.Explode
local StringFormat = string.format
local TableQuickCopy = table.QuickCopy
local TableSort = table.sort
local ToDebugString = table.ToDebugString
local Traceback = debug.traceback
local xpcall = xpcall

local Hook = Shine.Hook

Shine.Plugins = {}

local AutoLoadPath = "config://shine/AutoLoad.json"
local ExtensionPath = "lua/shine/extensions/"

function Shine.GetPluginFile( Plugin, Path )
	return StringFormat( "%s%s/%s", ExtensionPath, Plugin, Path )
end

function Shine.LoadPluginFile( Plugin, Path )
	return Script.Load( Shine.GetPluginFile( Plugin, Path ) )
end

function Shine.GetModuleFile( ModuleName )
	return StringFormat( "lua/shine/modules/%s", ModuleName )
end

function Shine.LoadPluginModule( ModuleName, Plugin, ... )
	Plugin = Plugin or _G.Plugin
	Shine.AssertAtLevel( Plugin and Plugin.AddModule,
		"Called LoadPluginModule too early! Make sure the plugin has been registered first.", 3 )

	local File = loadfile( Shine.GetModuleFile( ModuleName ) )
	return File( Plugin, ... )
end

--Here we collect every extension file so we can be sure it exists before attempting to load it.
local Files = {}
Shared.GetMatchingFileNames( ExtensionPath.."*.lua", true, Files )
local PluginFiles = {}

--Convert to faster table.
for i = 1, #Files do
	PluginFiles[ Files[ i ] ] = true
end

--Include the base plugin.
include "lua/shine/core/shared/base_plugin.lua"

local PluginMeta = Shine.BasePlugin

function Shine:RegisterExtension( Name, Table, Options )
	self.Plugins[ Name ] = setmetatable( Table, PluginMeta )

	Table.BaseClass = PluginMeta
	Table.__Name = Name

	if Client then
		self.Locale:RegisterSource( Name, "locale/shine/extensions/"..Name )
	end

	-- Copy (by reference) all modules from the base of the plugin
	-- This allows plugins to add their own modules progressively.
	local function SetupModules( Base )
		Table.Modules = TableQuickCopy( Base.Modules )
		Table:SetupDispatcher()
	end

	if not Options then
		SetupModules( PluginMeta )
		return
	end

	local Base = Options.Base
	if not Base then
		SetupModules( PluginMeta )
		return
	end

	if not self.Plugins[ Base ] then
		if not self:LoadExtension( Base, true ) then
			SetupModules( PluginMeta )
			return
		end
	end

	local ParentPlugin = self.Plugins[ Base ]

	if ParentPlugin.__Inherit == Table then
		self.Plugins[ Name ] = nil

		error( StringFormat(
			"[Shine] Cyclic dependency detected. Plugin %s depends on %s while %s also depends on %s.",
			Name, Base, Base, Name ) )
	end

	Table.__Inherit = ParentPlugin
	Table.__InheritBlacklist = Options.BlacklistKeys
	Table.__InheritWhitelist = Options.WhitelistKeys

	SetupModules( ParentPlugin )
end

local LoadingErrors = {}

function Shine:LoadExtension( Name, DontEnable )
	Name = Name:lower()

	if LoadingErrors[ Name ] then return false, LoadingErrors[ Name ] end
	if self.Plugins[ Name ] then return true end

	local ClientFile = StringFormat( "%s%s/client.lua", ExtensionPath, Name )
	local ServerFile = StringFormat( "%s%s/server.lua", ExtensionPath, Name )
	local SharedFile = StringFormat( "%s%s/shared.lua", ExtensionPath, Name )

	local IsShared = PluginFiles[ SharedFile ]
		or ( PluginFiles[ ClientFile ] and PluginFiles[ ServerFile ] )
	if PluginFiles[ SharedFile ] then
		include( SharedFile )

		local Plugin = self.Plugins[ Name ]
		if not Plugin then
			return false, "plugin did not register itself"
		end

		-- Don't load irrelevant plugins. Make sure we stop before network messages.
		local CanLoad, FailureReason = self:CanPluginLoad( Plugin )
		if not CanLoad then
			self.Plugins[ Name ] = nil
			return false, FailureReason
		end

		Plugin.IsShared = true

		if Plugin.SetupDataTable then -- Networked variables.
			Plugin:SetupDataTable()
			Plugin:InitDataTable( Name )
		end
	end

	-- Client plugins load automatically, but enable themselves later when told to.
	if Client then
		local OldValue = Plugin
		Plugin = self.Plugins[ Name ]

		if PluginFiles[ ClientFile ] then
			include( ClientFile )
		elseif not self.Plugins[ Name ] then
			-- No client file, and no shared file, or shared did not register.
			return false, "plugin did not register itself"
		end

		Plugin = OldValue -- Just in case someone else uses Plugin as a global...

		local Plugin = self.Plugins[ Name ]
		if not Plugin then
			return false, "plugin did not register itself"
		end

		local CanLoad, FailureReason = self:CanPluginLoad( Plugin )
		if not CanLoad then
			self.Plugins[ Name ] = nil
			return false, FailureReason
		end

		Plugin.IsClient = true

		return true
	end

	if not PluginFiles[ ServerFile ] then
		ServerFile = StringFormat( "%s%s.lua", ExtensionPath, Name )

		if not PluginFiles[ ServerFile ] then
			local Found

			local SearchTerm = StringFormat( "/%s.lua", Name )

			-- In case someone uses a different case file name to the plugin name...
			for File in pairs( PluginFiles ) do
				local LowerF = File:lower()

				if LowerF:find( SearchTerm, 1, true ) then
					Found = true
					ServerFile = File

					break
				end
			end

			if not Found then
				return false, "plugin does not exist."
			end
		end
	end

	-- Global value so that the server file has access to the same table the shared one created.
	local OldValue = Plugin

	if IsShared then
		Plugin = self.Plugins[ Name ]
	end

	include( ServerFile )

	-- Clean it up afterwards ready for the next extension.
	if IsShared then
		Plugin = OldValue
	end

	local Plugin = self.Plugins[ Name ]
	if not Plugin then
		return false, "plugin did not register itself."
	end

	local CanLoad, FailureReason = self:CanPluginLoad( Plugin )
	if not CanLoad then
		self.Plugins[ Name ] = nil
		return false, FailureReason
	end

	Plugin.IsShared = IsShared and true or nil

	if DontEnable then return true end

	return self:EnableExtension( Name )
end

function Shine:CanPluginLoad( Plugin )
	if self.IsNS2Combat and Plugin.NS2Only then
		return false, "plugin not compatible with NS2:Combat"
	end

	local Gamemode = Shine.GetGamemode()

	-- Allow external mods/gamemodes to decide whether the plugin can load if they know a plugin is compatible.
	local Allowed = Hook.Call( "CanPluginLoad", Plugin, Gamemode )
	if Allowed ~= nil then
		if not Allowed then
			return false, "plugin not compatible with gamemode: "..Gamemode
		end

		return true
	end

	-- Plugin has explicitly requested to be disabled for the gamemode.
	local IsDisabled = Plugin.DisabledGamemodes and Plugin.DisabledGamemodes[ Gamemode ]
	-- Plugin has expliclty requested to only be enabled for certain gamemodes.
	local IsNotEnabled = Plugin.EnabledGamemodes and not Plugin.EnabledGamemodes[ Gamemode ]

	if IsDisabled or IsNotEnabled then
		return false, "plugin not compatible with gamemode: "..Gamemode
	end

	return true
end

local HasFirstThinkOccurred
Hook.Add( "OnFirstThink", "ExtensionFirstThink", function()
	HasFirstThinkOccurred = true
end )

-- Handles dispatching plugin events efficiently.
local Dispatcher

local function CheckPluginConflicts( self, Conflicts )
	if not Conflicts or not Server then return true end

	local DisableThem = Conflicts.DisableThem
	local DisableUs = Conflicts.DisableUs

	if DisableUs then
		for i = 1, #DisableUs do
			local Plugin = DisableUs[ i ]

			local PluginTable = self.Plugins[ Plugin ]
			local SetToEnable = self.Config.ActiveExtensions[ Plugin ]

			-- Halt our enabling, we're not allowed to load with this plugin enabled.
			if SetToEnable or ( PluginTable and PluginTable.Enabled ) then
				return false, StringFormat( "unable to load alongside '%s'.", Plugin )
			end
		end
	end

	if DisableThem then
		for i = 1, #DisableThem do
			local Plugin = DisableThem[ i ]

			local PluginTable = self.Plugins[ Plugin ]
			local SetToEnable = self.Config.ActiveExtensions[ Plugin ]

			-- Don't allow them to load, or unload them if they have already.
			if SetToEnable or ( PluginTable and PluginTable.Enabled ) then
				self.Config.ActiveExtensions[ Plugin ] = false

				self:UnloadExtension( Plugin )
			end
		end
	end

	return true
end

local function CheckDependencies( self, Dependencies )
	if not Dependencies then return true end

	for i = 1, #Dependencies do
		local Dependency = Dependencies[ i ]
		if not self.Config.ActiveExtensions[ Dependency ]
		and not self:IsExtensionEnabled( Dependency ) then
			return false, StringFormat( "plugin depends on '%s'", Dependency )
		end
	end

	return true
end

-- Shared extensions need to be enabled once the server tells it to.
function Shine:EnableExtension( Name, DontLoadConfig )
	if LoadingErrors[ Name ] then return false, LoadingErrors[ Name ] end

	local Plugin = self.Plugins[ Name ]
	if not Plugin then
		return false, LoadingErrors[ Name ] or "plugin does not exist"
	end

	local FirstEnable = Plugin.Enabled == nil

	if Plugin.Enabled then
		self:UnloadExtension( Name )
	end

	do
		-- Deal with inter-plugin conflicts.
		local OK, Err = CheckPluginConflicts( self, Conflicts )
		if not OK then
			return OK, Err
		end
	end

	do
		-- Deal with plugin dependencies.
		local OK, Err = CheckDependencies( self, Plugin.DependsOnPlugins )
		if not OK then
			return OK, Err
		end
	end

	if Plugin.HasConfig and not DontLoadConfig then
		local Success, Err = pcall( Plugin.LoadConfig, Plugin )
		if not Success then
			return false, StringFormat( "Error while loading config: %s", Err )
		end
	end

	local Success, Loaded, Err = pcall( Plugin.Initialise, Plugin )

	--There was a Lua error.
	if not Success then
		pcall( Plugin.Cleanup, Plugin )
		--Just in case the cleanup failed, we have to make sure this has run.
		PluginMeta.Cleanup( Plugin )

		Plugin.Enabled = nil

		return false, StringFormat( "Lua error: %s", Loaded )
	end

	--The plugin has refused to load.
	if not Loaded then
		Plugin.Enabled = nil

		return false, Err
	end

	if FirstEnable and HasFirstThinkOccurred and Plugin.OnFirstThink then
		Plugin:OnFirstThink()
	end

	-- Flush event cache. We can't be smarter than this, because it could be loading mid-event call.
	-- If we edited the specific event table at that point, it would potentially cause double event calls
	-- or missed event calls. Plugin load/unload should be a rare occurence anyway.
	Dispatcher:FlushCache()
	Plugin.Enabled = true

	--We need to inform clients to enable the client portion.
	if Server and Plugin.IsShared and not self.GameIDs:IsEmpty() then
		Shine.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = true }, true )
	end

	Hook.Call( "OnPluginLoad", Name, Plugin, Plugin.IsShared )

	return true
end

local OnCleanupError = Shine.BuildErrorHandler( "Plugin cleanup error" )

function Shine:UnloadExtension( Name )
	local Plugin = self.Plugins[ Name ]

	if not Plugin then return end
	if not Plugin.Enabled then return end

	Plugin.Enabled = false

	-- Flush event cache.
	Dispatcher:FlushCache()

	-- Make sure cleanup doesn't break us by erroring.
	local Success = xpcall( Plugin.Cleanup, OnCleanupError, Plugin )
	if not Success then
		PluginMeta.Cleanup( Plugin )
	end

	if Server and Plugin.IsShared and not self.GameIDs:IsEmpty() then
		Shine.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = false }, true )
	end

	Hook.Call( "OnPluginUnload", Name, Plugin, Plugin.IsShared )
end

--[[
	Returns whether an extension is loaded, and its table if it is.
]]
function Shine:IsExtensionEnabled( Name )
	local Plugin = self.Plugins[ Name ]

	if Plugin then
		if Plugin.Enabled then
			return true, Plugin
		else
			return false, Plugin
		end
	end

	return false
end

-- Store a list of all plugins in existence. When the server config loads, we use it.
local ClientPlugins = {}
local AllPlugins = {}
Shine.AllPlugins = AllPlugins

local AllPluginsArray = {}
Shine.AllPluginsArray = AllPluginsArray

do
	Dispatcher = Shine.EventDispatcher( AllPluginsArray )

	function Dispatcher:GetListener( PluginName )
		return Shine.Plugins[ PluginName ]
	end

	function Dispatcher:IsListenerValidForEvent( Plugin, Event )
		return Plugin and Plugin.Enabled and IsType( Plugin[ Event ], "function" )
	end

	function Dispatcher:CallEvent( Plugin, Method, OnError, Event, ... )
		local Success, a, b, c, d, e, f = xpcall( Method, OnError, Plugin, ... )

		if not Success then
			Plugin.__HookErrors = ( Plugin.__HookErrors or 0 ) + 1
			Shine:DebugPrint( "[Hook Error] %s hook failed from plugin '%s'. Error count: %i.",
				true, Event, Plugin.__Name, Plugin.__HookErrors )

			if Plugin.__HookErrors >= 10 then
				Shine:DebugPrint( "Unloading plugin '%s' for too many hook errors (%i).",
					true, Plugin.__Name, Plugin.__HookErrors )

				Plugin.__HookErrors = 0

				Shine:UnloadExtension( Plugin.__Name )
			end

			return nil
		end

		return a, b, c, d, e, f
	end

	--[[
		Calls an event on all active extensions.
		Called by the hook system, should not be called directly.
	]]
	function Shine:CallExtensionEvent( Event, OnError, ... )
		return Dispatcher:DispatchEvent( Event, OnError, Event, ... )
	end
end

local PluginFileMapping = {}

local function AddPluginFile( Name, File )
	PluginFileMapping[ Name ] = PluginFileMapping[ Name ] or {}
	PluginFileMapping[ Name ][ File ] = true
end

local function AddToPluginsLists( Name )
	if not AllPlugins[ Name ] then
		AllPlugins[ Name ] = true
		AllPluginsArray[ #AllPluginsArray + 1 ] = Name

		if Client then
			-- Register plugin locales here so that server-only plugins can send translated messages.
			Shine.Locale:RegisterSource( Name, "locale/shine/extensions/"..Name )
		end
	end
end

--[[
	Prepare shared plugins.

	Important to note: Shine does not support hot loading plugin files.
	That is, it will only know about plugin files that were present when it started.
]]
for Path in pairs( PluginFiles ) do
	local Folders = StringExplode( Path, "/" )
	local Name = Folders[ 4 ]
	local File = Folders[ 5 ]

	if File then
		if not ClientPlugins[ Name ] then
			local LoweredFileName = File:lower()

			if LoweredFileName == "shared.lua" then
				ClientPlugins[ Name ] = "boolean" -- Generate the network message.
				AddToPluginsLists( Name )
			elseif LoweredFileName == "server.lua" or LoweredFileName == "client.lua" then
				AddToPluginsLists( Name )
			end

			-- Shared plugins should load into memory for network messages.
			local Success, Err = Shine:LoadExtension( Name, true )
			if not Success then
				-- Remember the first loading error, as subsequent errors will be because
				-- the plugin does not exist in Shine.Plugins.
				LoadingErrors[ Name ] = Err
			end
		end
	else
		File = Name
		Name = Name:gsub( "%.lua", "" )

		AddToPluginsLists( Name )
	end

	AddPluginFile( Name, File )
end

-- Alphabetical order for hook calling consistency.
Shine.Stream( AllPluginsArray ):Filter( function( Name )
	-- Filter out plugins that exist on the side we're not.
	local Mapping = PluginFileMapping[ Name ]

	-- Client-side only plugin will not have server.lua, shared.lua or pluginname.lua.
	if Server and not Mapping[ "server.lua" ] and not Mapping[ "shared.lua" ] and not Mapping[ Name..".lua" ] then
		return false
	end

	-- Server-side only will not have shared.lua or client.lua.
	if Client and not Mapping[ "client.lua" ] and not Mapping[ "shared.lua" ] then
		return false
	end

	return true
end ):Sort( function( A, B )
	return A:lower() < B:lower()
end )

Shared.RegisterNetworkMessage( "Shine_PluginSync", ClientPlugins )
Shared.RegisterNetworkMessage( "Shine_PluginEnable", {
	Plugin = "string (25)",
	Enabled = "boolean"
} )

if Server then
	Shine.Hook.Add( "ClientConfirmConnect", "PluginSync", function( Client )
		local Message = {}

		for Name in pairs( ClientPlugins ) do
			if Shine.Plugins[ Name ] and Shine.Plugins[ Name ].Enabled then
				Message[ Name ] = true
			else
				Message[ Name ] = false
			end
		end

		Shine.SendNetworkMessage( Client, "Shine_PluginSync", Message, true )
	end )

	return
end

Client.HookNetworkMessage( "Shine_PluginSync", function( Data )
	for Name, Enabled in pairs( Data ) do
		if Enabled then
			Shine:EnableExtension( Name )
		end
	end

	Shine.AddStartupMessage = nil

	local StartupMessages = Shine.StartupMessages

	Notify( "==============================" )
	Notify( "Shine started up successfully." )

	for i = 1, #StartupMessages do
		Notify( StartupMessages[ i ] )
	end

	Notify( "==============================" )

	Shine.StartupMessages = nil
end )

Client.HookNetworkMessage( "Shine_PluginEnable", function( Data )
	local Name = Data.Plugin
	local Enabled = Data.Enabled

	if Enabled then
		Shine:EnableExtension( Name )
	else
		Shine:UnloadExtension( Name )
	end
end )

--[[
	Adds a plugin to be auto loaded on the client.
	This should only be used for client side plugins, not shared.

	Inputs: Plugin name, boolean AutoLoad.
]]
function Shine:SetPluginAutoLoad( Name, AutoLoad )
	if not self.AutoLoadPlugins then return end

	AutoLoad = AutoLoad or false

	self.AutoLoadPlugins[ Name ] = AutoLoad

	self.SaveJSONFile( self.AutoLoadPlugins, AutoLoadPath )
end

local DefaultAutoLoad = {
	chatbox = true
}

function Shine:CreateDefaultAutoLoad()
	self.AutoLoadPlugins = DefaultAutoLoad

	self.SaveJSONFile( self.AutoLoadPlugins, AutoLoadPath )
end

Shine:RegisterClientCommand( "sh_loadplugin_cl", function( Name )
	Shine:SetPluginAutoLoad( Name, true )
	local Success, Err = Shine:EnableExtension( Name )

	if Success then
		Print( "[Shine] Enabled the '%s' extension.", Name )
	else
		Print( "[Shine] Could not load extension '%s': %s", Name, Err )
	end
end ):AddParam{ Type = "string", TakeRestOfLine = true }

Shine:RegisterClientCommand( "sh_unloadplugin_cl", function( Name )
	Shine:SetPluginAutoLoad( Name, false )
	Shine:UnloadExtension( Name )

	Print( "[Shine] Disabled the '%s' extension.", Name )
end ):AddParam{ Type = "string", TakeRestOfLine = true }

Hook.Add( "OnMapLoad", "AutoLoadExtensions", function()
	local AutoLoad = Shine.LoadJSONFile( AutoLoadPath )

	if not AutoLoad or not next( AutoLoad ) then
		Shine:CreateDefaultAutoLoad()
	else
		Shine.AutoLoadPlugins = AutoLoad
	end

	if Shine.CheckConfig( Shine.AutoLoadPlugins, DefaultAutoLoad, true ) then
		Shine.SaveJSONFile( Shine.AutoLoadPlugins, AutoLoadPath )
	end

	for Plugin, Load in SortedPairs( Shine.AutoLoadPlugins ) do
		if Load then
			Shine:EnableExtension( Plugin )
		end
	end
end, -20 )
