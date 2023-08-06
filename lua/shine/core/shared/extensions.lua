--[[
	Shine extension system.

	Supports server side, client side and shared plugins.
]]

local Shine = Shine
local IsType = Shine.IsType

-- loadfile allows catching errors in the file being executed, Script.Load does not...
local getmetatable = getmetatable
local loadfile = loadfile
local next = next
local pairs = pairs
local Notify = Shared.Message
local pcall = pcall
local setmetatable = setmetatable
local StringEndsWith = string.EndsWith
local StringExplode = string.Explode
local StringFormat = string.format
local StringGSub = string.gsub
local StringLower = string.lower
local TableQuickCopy = table.QuickCopy
local TableSort = table.sort
local ToDebugString = table.ToDebugString
local tostring = tostring
local Traceback = debug.traceback
local xpcall = xpcall

local Hook = Shine.Hook

Shine.Plugins = {}

local AutoLoadPath = "config://shine/AutoLoad.json"
local ExtensionPath = "lua/shine/extensions/"

-- Here we collect every extension file so we can be sure it exists before attempting to load it.
local Files = {}
Shared.GetMatchingFileNames( ExtensionPath.."*.lua", true, Files )
local PluginFiles = {}

-- Map case-insensitive path to real path for case-sensitive file systems.
for i = 1, #Files do
	PluginFiles[ StringLower( Files[ i ] ) ] = Files[ i ]
end

function Shine.GetPluginFile( PluginName, Path )
	local FilePath = StringFormat( "%s%s/%s", ExtensionPath, PluginName, Path )
	return PluginFiles[ StringLower( FilePath ) ] or FilePath
end

local function DoFileWithArgs( FilePath, ... )
	local File, Err = loadfile( FilePath )
	if not File then
		error( Err, 2 )
	end
	return File( ... )
end

function Shine.LoadPluginFile( PluginName, Path, ... )
	return DoFileWithArgs( Shine.GetPluginFile( PluginName, Path ), ... )
end

function Shine.GetModuleFile( ModuleName )
	return StringFormat( "lua/shine/modules/%s", ModuleName )
end

function Shine.LoadPluginModule( ModuleName, Plugin, ... )
	Plugin = Plugin or _G.Plugin
	Shine.AssertAtLevel( Plugin and Plugin.AddModule,
		"Called LoadPluginModule too early! Make sure the plugin has been registered first.", 3 )

	return DoFileWithArgs( Shine.GetModuleFile( ModuleName ), Plugin, ... )
end

-- Include the base plugin.
Script.Load "lua/shine/core/shared/base_plugin.lua"

local PluginMeta = Shine.BasePlugin

local function MakePlugin( Name, Table )
	local Plugin = setmetatable( Table or {}, PluginMeta )

	Plugin.BaseClass = PluginMeta
	Plugin.__Name = Name

	return Plugin
end
Shine.Plugin = MakePlugin

local function IsPlugin( Value )
	return getmetatable( Value ) == PluginMeta
end
Shine.IsPlugin = IsPlugin

function Shine:RegisterExtension( Name, Plugin, Options )
	Shine.TypeCheck( Name, "string", 1, "RegisterExtension" )
	Shine.TypeCheck( Plugin, "table", 2, "RegisterExtension" )
	Shine.TypeCheck( Options, { "nil", "table" }, 3, "RegisterExtension" )

	if not IsPlugin( Plugin ) then
		Plugin = MakePlugin( Name, Plugin )
	end

	self.Plugins[ Name ] = Plugin

	if Client then
		self.Locale:RegisterSource( Name, "locale/shine/extensions/"..Name )
	end

	-- Copy (by reference) all modules from the base of the plugin.
	-- This allows plugins to add their own modules progressively.
	local function SetupModules( Base )
		Plugin:AddBaseModules( Base.Modules )
		Plugin:SetupDispatcher()
	end

	local Base = Options and Options.Base
	if not IsType( Base, "string" ) then
		SetupModules( PluginMeta )
		return
	end

	if not self.Plugins[ Base ] then
		if not self:LoadExtension( Base, true ) then
			error( StringFormat(
				"Unable to make plugin %s inherit from %s as %s could not be loaded.",
				Name, Base, Base
			), 2 )
		end
	end

	local ParentPlugin = self.Plugins[ Base ]
	if ParentPlugin.__Inherit == Plugin then
		self.Plugins[ Name ] = nil

		error( StringFormat(
			"Cyclic dependency detected. Plugin %s depends on %s while %s also depends on %s.",
			Name, Base, Base, Name
		), 2 )
	end

	local BlacklistKeys = Options.BlacklistKeys
	local WhitelistKeys = Options.WhitelistKeys

	-- Compile inheritance rules into a single predicate.
	local KeyPredicate = function() return true end
	if BlacklistKeys then
		KeyPredicate = Predicates.And( KeyPredicate, function( Key ) return not BlacklistKeys[ Key ] end )
	end
	if WhitelistKeys then
		KeyPredicate = Predicates.And( KeyPredicate, function( Key ) return WhitelistKeys[ Key ] end )
	end

	Plugin.__CanInherit = KeyPredicate
	Plugin.__Inherit = ParentPlugin
	Plugin.__InheritBlacklist = BlacklistKeys
	Plugin.__InheritWhitelist = WhitelistKeys

	SetupModules( ParentPlugin )
end

local LoadingErrors = {}

do
	local OnLoadError = Shine.BuildErrorHandler( "Plugin loading error" )

	local function AutoRegisterExtension( self, Name, PluginTable, Options )
		return xpcall( self.RegisterExtension, OnLoadError, self, Name, PluginTable, Options )
	end

	local function LoadPluginScript( PluginFilePath, ... )
		local PluginScript, Err = loadfile( PluginFiles[ PluginFilePath ] )
		if not PluginScript then
			-- Syntax error, report it and fail here.
			OnLoadError( Err )
			return false, Err
		end

		return xpcall( PluginScript, OnLoadError, ... )
	end

	local function LoadWithGlobalPlugin( Name, PluginFilePath, PluginTable )
		-- Maintain legacy behaviour of setting the global Plugin value.
		local OldValue = _G.Plugin
		_G.Plugin = PluginTable

		-- Pass the plugin table directly into the script function to avoid needing the global.
		local Success, PluginTable, Options = LoadPluginScript( PluginFilePath, PluginTable, Name )

		_G.Plugin = OldValue -- Just in case someone else uses Plugin as a global...

		return Success, PluginTable, Options
	end

	local function HandleAutoRegister( self, Name, Success, PluginTable, Options )
		if not Success then
			return false, "script error while loading plugin (see the log for details)"
		end

		local Plugin = self.Plugins[ Name ]
		if not Plugin then
			if IsType( PluginTable, "table" ) then
				-- Plugin file returned the plugin table, so register it for them.
				if not AutoRegisterExtension( self, Name, PluginTable, Options ) then
					self.Plugins[ Name ] = nil
					return false, "script error while loading plugin (see the log for details)"
				end
				Plugin = PluginTable
			else
				return false, "plugin did not register itself"
			end
		end

		return true, Plugin
	end

	local function SetupNetworking( Name, Plugin )
		if not Shine.IsCallable( Plugin.SetupDataTable ) then return true end

		local Success, Err = xpcall( Plugin.SetupDataTable, OnLoadError, Plugin )
		if not Success then
			return false, "error during networking setup (see log), this may cause invalid data errors for clients!"
		end

		Plugin:InitDataTable( Name )

		return true
	end

	local function WarnAboutInconsistentCanLoad( self, Name, Plugin, VMName, SharedPluginCanLoad )
		if not Plugin.IsShared or not SharedPluginCanLoad then return end

		Print(
			"[Shine] [Warn] Plugin %s has been prevented from loading on the %s, "..
			"but not in shared.lua. If the %s does not prevent loading the plugin "..
			"then clients will be disconnected with invalid data. Use shared.lua "..
			"to declare EnabledGamemodes/DisabledGamemodes (or a shared CanPluginLoad hook) to avoid this.",
			Name, VMName, VMName == "client" and "server" or "client"
		)
	end

	function Shine:LoadExtension( Name, DontEnable )
		Shine.TypeCheck( Name, "string", 1, "LoadExtension" )

		Name = StringLower( Name )

		if LoadingErrors[ Name ] then return false, LoadingErrors[ Name ] end
		if self.Plugins[ Name ] then return true end

		local ClientFile = StringFormat( "%s%s/client.lua", ExtensionPath, Name )
		local ServerFile = StringFormat( "%s%s/server.lua", ExtensionPath, Name )
		local SharedFile = StringFormat( "%s%s/shared.lua", ExtensionPath, Name )

		local IsShared = PluginFiles[ SharedFile ]
			or ( PluginFiles[ ClientFile ] and PluginFiles[ ServerFile ] )
		local SharedPluginCanLoad
		if PluginFiles[ SharedFile ] then
			local IsLoaded, Plugin = HandleAutoRegister( self, Name, LoadPluginScript( SharedFile, Name ) )
			if not IsLoaded then
				return false, Plugin
			end

			Plugin.IsShared = true
			-- Check if the plugin can load after loading shared.lua so we can check for consistency.
			SharedPluginCanLoad = self:CanPluginLoad( Plugin )
		end

		-- Client plugins load automatically, but enable themselves later when told to.
		if Client then
			if PluginFiles[ ClientFile ] then
				local Success, PluginTable, Options
				if IsShared and self.Plugins[ Name ] then
					Success = LoadWithGlobalPlugin( Name, ClientFile, self.Plugins[ Name ] )
				else
					Success, PluginTable, Options = LoadPluginScript( ClientFile, Name )
				end

				local IsLoaded, Plugin = HandleAutoRegister( self, Name, Success, PluginTable, Options )
				if not IsLoaded then
					return false, Plugin
				end
			end

			local Plugin = self.Plugins[ Name ]
			if not Plugin then
				return false, "plugin did not register itself"
			end

			local CanLoad, FailureReason = self:CanPluginLoad( Plugin )
			if not CanLoad then
				WarnAboutInconsistentCanLoad( self, Name, Plugin, "client", SharedPluginCanLoad )
				self.Plugins[ Name ] = nil
				return false, FailureReason
			end

			Plugin.IsClient = true

			-- Setup networked variables after all files have executed.
			return SetupNetworking( Name, Plugin )
		end

		if not PluginFiles[ ServerFile ] then
			-- No folder, look for a single file named after the plugin.
			ServerFile = StringFormat( "%s%s.lua", ExtensionPath, Name )

			if not PluginFiles[ ServerFile ] and not self.Plugins[ Name ] then
				return false, "unable to find server-side plugin file"
			end
		end

		local Plugin = self.Plugins[ Name ]
		if PluginFiles[ ServerFile ] then
			local Success, PluginTable, Options
			if IsShared and Plugin then
				Success = LoadWithGlobalPlugin( Name, ServerFile, Plugin )
			else
				Success, PluginTable, Options = LoadPluginScript( ServerFile, Name )
			end

			Success, Plugin = HandleAutoRegister( self, Name, Success, PluginTable, Options )
			if not Success then
				return false, Plugin
			end
		end

		local CanLoad, FailureReason = self:CanPluginLoad( Plugin )
		if not CanLoad then
			WarnAboutInconsistentCanLoad( self, Name, Plugin, "server", SharedPluginCanLoad )
			self.Plugins[ Name ] = nil
			return false, FailureReason
		end

		Plugin.IsShared = IsShared and true or nil

		-- Setup networked variables after all files have executed.
		local Success, Err = SetupNetworking( Name, Plugin )
		if not Success then
			return false, Err
		end

		if DontEnable then return true end

		return self:EnableExtension( Name )
	end
end

function Shine:CanPluginLoad( Plugin )
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

local AddPluginHook
local HasPluginHook
local RemovePluginHook
local RemoveAllPluginHooks
do
	local CodeGen = require "shine/lib/codegen"
	local select = select

	local OnError = Shine.BuildErrorHandler( "Plugin hook error" )

	local Callers = CodeGen.MakeFunctionGenerator( {
		Template = [[local OnError, Shine, xpcall = ...
			return function( Plugin, Method, Event{Arguments} )
				local Success, a, b, c, d, e, f = xpcall( Method, OnError, Plugin{Arguments} )

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
		]],
		ChunkName = "@lua/shine/core/shared/extensions.lua/CallEvent",
		-- This should match the value used in the hook system.
		InitialSize = 10,
		Args = { OnError, Shine, xpcall }
	} )

	local EventKey = Shine.TypeDef()
	function EventKey:Init( Plugin )
		self.Plugin = Plugin
		return self
	end
	function EventKey:__tostring()
		return StringFormat( "Plugin - %s", self.Plugin:GetName() )
	end

	local EventCaller = Shine.TypeDef()
	function EventCaller:Init( Plugin, Event )
		self.Plugin = Plugin
		self.Event = Event
		return self
	end

	function EventCaller:__call( ... )
		return Callers[ select( "#", ... ) ]( self.Plugin, self.Plugin[ self.Event ], self.Event, ... )
	end

	function EventCaller:__tostring()
		return StringFormat( "Shine.Plugins.%s:%s()", self.Plugin:GetName(), self.Event )
	end

	local PluginEventKeys = {}
	local PluginEvents = setmetatable( {}, {
		__index = function( self, Key )
			local Events = Shine.Set()

			self[ Key ] = Events

			return Events
		end
	} )
	local EventsWithPlugins = Shine.UnorderedMultimap()

	AddPluginHook = function( Plugin, Event )
		if not IsType( Plugin[ Event ], "function" ) then return end

		local Key = PluginEventKeys[ Plugin ] or EventKey( Plugin )
		PluginEventKeys[ Plugin ] = Key

		PluginEvents[ Plugin ]:Add( Event )
		EventsWithPlugins:Add( Event, Plugin )

		Hook.Add( Event, Key, EventCaller( Plugin, Event ), Hook.MAX_PRIORITY + 0.5 )
	end

	HasPluginHook = function( Event )
		return EventsWithPlugins:Get( Event ) ~= nil
	end

	RemovePluginHook = function( Plugin, Event )
		Hook.Remove( Event, PluginEventKeys[ Plugin ] )
		EventsWithPlugins:RemoveKeyValue( Event, Plugin )
	end

	RemoveAllPluginHooks = function( Plugin )
		local Events = PluginEvents[ Plugin ]

		for Event in Events:Iterate() do
			RemovePluginHook( Plugin, Event )
		end

		PluginEventKeys[ Plugin ] = nil
		PluginEvents[ Plugin ] = nil
	end
end

do
	local OnInitError = Shine.BuildErrorHandler( "Plugin initialisation error" )
	local function MarkAsDisabled( Plugin, FirstEnable )
		if FirstEnable then
			Plugin.Enabled = nil
		else
			Plugin.Enabled = false
		end
	end

	local function NotifyInitError( Name, Err )
		if not Server then return end

		Shine.SystemNotifications:AddNotification( {
			Type = Shine.SystemNotifications.Type.ERROR,
			Message = {
				Source = "Core",
				TranslationKey = "ERROR_PLUGIN_INIT_ERROR",
				Context = tostring( Err )
			},
			Source = {
				Type = Shine.SystemNotifications.Source.PLUGIN,
				ID = Name
			}
		} )
	end

	local function ResetPluginHooks( PluginBeingLoaded )
		local Events = Hook.GetKnownEvents()
		for i = 1, #Events do
			if IsType( PluginBeingLoaded[ Events[ i ] ], "function" ) then
				if HasPluginHook( Events[ i ] ) then
					-- If there's at least one plugin hooked to this event, re-add all plugins in the correct order.
					Shine:SetupExtensionEvents( Events[ i ] )
				else
					-- Otherwise just add the new plugin.
					AddPluginHook( PluginBeingLoaded, Events[ i ] )
				end
			end
		end
	end

	-- Shared extensions need to be enabled once the server tells it to.
	function Shine:EnableExtension( Name, DontLoadConfig )
		Shine.TypeCheck( Name, "string", 1, "EnableExtension" )

		Name = StringLower( Name )

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
			local OK, Err = CheckPluginConflicts( self, Plugin.Conflicts )
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

		-- Forget any previous module events before starting.
		Plugin:ResetModuleEventHistory()

		if Plugin.HasConfig and not DontLoadConfig then
			local Success, Err = xpcall( Plugin.LoadConfig, OnInitError, Plugin )
			if not Success then
				NotifyInitError( Name, Err )
				return false, StringFormat( "Error while loading config: %s", Err )
			end
		end

		local Success, Loaded, Err = xpcall( Plugin.Initialise, OnInitError, Plugin )
		if not Success then
			pcall( Plugin.Cleanup, Plugin )
			-- Just in case the cleanup failed, we have to make sure this has run.
			PluginMeta.Cleanup( Plugin )

			MarkAsDisabled( Plugin, FirstEnable )

			NotifyInitError( Name, Loaded )

			return false, StringFormat( "Lua error: %s", Loaded )
		end

		-- The plugin has refused to load.
		if not Loaded then
			MarkAsDisabled( Plugin, FirstEnable )

			return false, Err
		end

		-- Plugin authors shouldn't need to explicitly call this, as they may forget.
		if not Plugin:HasFiredModuleEvent( "Initialise" ) then
			Success, Err = xpcall( Plugin.BroadcastModuleEvent, OnInitError, Plugin, "Initialise" )

			if not Success then
				NotifyInitError( Name, Err )
				return false, StringFormat( "Lua error: %s", Err )
			end
		end

		Plugin.Enabled = true

		if FirstEnable and HasFirstThinkOccurred and Plugin.OnFirstThink then
			-- If this were called as a hook, an error would be a strike against the plugin's hook
			-- error count, so don't fail loading here if it fails.
			if not xpcall( Plugin.OnFirstThink, OnInitError, Plugin ) then
				Plugin.__HookErrors = ( Plugin.__HookErrors or 0 ) + 1
			end
		end

		-- Reset all hooks to maintain a consistent calling order.
		-- Loading an extension is a rare event, so the cost of this is acceptable.
		ResetPluginHooks( Plugin )

		-- We need to inform clients to enable the client portion.
		if Server and Plugin.IsShared and not self.GameIDs:IsEmpty() then
			Shine.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = true }, true )

			-- Sending network messages before this point will fail as they will arrive before the plugin has been
			-- enabled on the client.
			if IsType( Plugin.OnNetworkingReady, "function" ) then
				if not xpcall( Plugin.OnNetworkingReady, OnInitError, Plugin ) then
					Plugin.__HookErrors = ( Plugin.__HookErrors or 0 ) + 1
				end
			end
		end

		Hook.Broadcast( "OnPluginLoad", Name, Plugin, Plugin.IsShared )

		return true
	end
end

do
	local OnCleanupError = Shine.BuildErrorHandler( "Plugin cleanup error" )

	function Shine:UnloadExtension( Name )
		Shine.TypeCheck( Name, "string", 1, "UnloadExtension" )

		Name = StringLower( Name )

		local Plugin = self.Plugins[ Name ]
		if not Plugin or not Plugin.Enabled then return false end

		Plugin.Enabled = false

		-- Make sure cleanup doesn't break us by erroring.
		local Success = xpcall( Plugin.Cleanup, OnCleanupError, Plugin )
		if not Success then
			xpcall( PluginMeta.Cleanup, OnCleanupError, Plugin )
		-- Make sure the module "Cleanup" event is called (the base plugin's Cleanup method calls this).
		elseif not Plugin:HasFiredModuleEvent( "Cleanup" ) then
			xpcall( Plugin.BroadcastModuleEvent, OnCleanupError, Plugin, "Cleanup" )
		end

		Plugin:ResetModuleEventHistory()

		RemoveAllPluginHooks( Plugin )

		if Server and Plugin.IsShared and not self.GameIDs:IsEmpty() then
			Shine.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = false }, true )
		end

		Hook.Broadcast( "OnPluginUnload", Name, Plugin, Plugin.IsShared )

		return true
	end
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

function Shine:SetupExtensionEvents( Event )
	for i = 1, #AllPluginsArray do
		local PluginName = AllPluginsArray[ i ]
		local Plugin = Shine.Plugins[ PluginName ]

		if Plugin then
			RemovePluginHook( Plugin, Event )

			if Plugin.Enabled then
				AddPluginHook( Plugin, Event )
			end
		end
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

if Server then
	Server.AddRestrictedFileHashes( "lua/shine/extensions/*.lua" )
end

--[[
	Prepare shared plugins.

	Important to note: Shine does not support hot loading plugin files.
	That is, it will only know about plugin files that were present when it started.
]]
for Path in pairs( PluginFiles ) do
	-- Path is the lower-case path to the file, not the real path.
	local Folders = StringExplode( Path, "/", true )
	local Name = Folders[ 4 ]
	local File = Folders[ 5 ]

	if File then
		if not ClientPlugins[ Name ] then
			if File == "shared.lua" then
				ClientPlugins[ Name ] = "boolean" -- Generate the network message.
				AddToPluginsLists( Name )
			elseif File == "server.lua" or File == "client.lua" then
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
		Name = StringGSub( Name, "%.lua$", "" )

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
end ):Sort()

Shared.RegisterNetworkMessage( "Shine_PluginSync", ClientPlugins )
Shared.RegisterNetworkMessage( "Shine_PluginEnable", {
	Plugin = "string (25)",
	Enabled = "boolean"
} )

local OfficialExtensions

--[[
	Returns a set of all plugins that are officialy bundled by inspecting the official mod.

	This is used in the plugin list UI to indicate whether a plugin is official or not, it's not used as any form of
	trusted status or any other logic.

	While this could be overriden by a mod, please don't. The point of this is to differentiate between plugins that
	belong to the main mod (and thus issues should be raised there) vs. plugins that belong to other mods. It's not some
	shiny badge of honour that your plugins must have.
]]
function Shine.IsOfficialExtension( Name )
	if not OfficialExtensions then
		OfficialExtensions = Shine.UnorderedSet()

		local Files = {}
		ModServices.GetMatchingFileNamesInMod( 117887554, "lua/shine/extensions/*.lua", true, Files )

		for i = 1, #Files do
			local Folders = StringExplode( Files[ i ], "/", true )
			local ExtensionName = Folders[ 4 ]
			local File = Folders[ 5 ]

			if not File then
				File = ExtensionName
				ExtensionName = StringGSub( ExtensionName, "%.lua$", "" )
			end

			if StringEndsWith( File, ".lua" ) then
				OfficialExtensions:Add( ExtensionName )
			end
		end
	end
	return OfficialExtensions:Contains( Name )
end

if Server then
	Shine.Hook.Add( "ClientConnect", "PluginSync", function( Client )
		if Client:GetIsVirtual() then return end

		local Message = {}

		for Name in pairs( ClientPlugins ) do
			if Shine.Plugins[ Name ] and Shine.Plugins[ Name ].Enabled then
				Message[ Name ] = true
			else
				Message[ Name ] = false
			end
		end

		Shine.SendNetworkMessage( Client, "Shine_PluginSync", Message, true )
	end, Shine.Hook.MAX_PRIORITY )

	return
end

Shine.HookNetworkMessage( "Shine_PluginSync", function( Data )
	for Name, Enabled in SortedPairs( Data ) do
		if Enabled then
			Shine:EnableExtension( Name )
		end
	end

	-- Change startup messages to a no-op, in case plugins are enabled later.
	Shine.AddStartupMessage = function() end

	local StartupMessages = Shine.StartupMessages
	if not StartupMessages then return end

	Notify( "==============================" )
	Notify( "Shine started up successfully." )

	for i = 1, #StartupMessages do
		Notify( StartupMessages[ i ] )
	end

	Notify( "==============================" )

	Shine.StartupMessages = nil
end )

Shine.HookNetworkMessage( "Shine_PluginEnable", function( Data )
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

	AutoLoad = AutoLoad or nil

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
	Name = StringLower( Name )

	local Plugin = Shine.Plugins[ Name ]
	if Plugin and Plugin.IsShared then
		Print( "[Shine] You cannot load the '%s' plugin.", Name )
		return
	end

	local Success, Err = Shine:EnableExtension( Name )
	if Success then
		Shine:SetPluginAutoLoad( Name, true )
		Print( "[Shine] Enabled the '%s' plugin.", Name )
	else
		Print( "[Shine] Could not load plugin '%s': %s", Name, Err )
	end
end ):AddParam{ Type = "string", TakeRestOfLine = true }

Shine:RegisterClientCommand( "sh_unloadplugin_cl", function( Name )
	Name = StringLower( Name )

	local Plugin = Shine.Plugins[ Name ]
	if Plugin and Plugin.IsShared then
		Print( "[Shine] You cannot unload the '%s' plugin.", Name )
		return
	end

	Shine:SetPluginAutoLoad( Name, false )
	if Shine:UnloadExtension( Name ) then
		Print( "[Shine] Disabled the '%s' plugin.", Name )
	else
		Print( "[Shine] No plugin named '%s' is loaded.", Name )
	end
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

	for PluginName, Load in SortedPairs( Shine.AutoLoadPlugins ) do
		if Load then
			local Plugin = Shine.Plugins[ PluginName ]
			if not Plugin or not Plugin.IsShared then
				Shine:EnableExtension( PluginName )
			end
		end
	end
end, Shine.Hook.MAX_PRIORITY + 1 )
