--[[
	Shine extension system.

	Supports server side, client side and shared plugins.
]]

local Shine = Shine

local include = Script.Load
local next = next
local pairs = pairs
local Notify = Shared.Message
local pcall = pcall
local setmetatable = setmetatable
local StringExplode = string.Explode
local StringFormat = string.format
local ToDebugString = table.ToDebugString
local Traceback = debug.traceback
local xpcall = xpcall

local Hook = Shine.Hook

Shine.Plugins = {}

local AutoLoadPath = "config://shine/AutoLoad.json"
local ExtensionPath = "lua/shine/extensions/"

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

	if Options then
		local Base = Options.Base
		if not Base then return end
		
		if not self.Plugins[ Base ] then
			if not self:LoadExtension( Base, true ) then
				return
			end
		end

		Table.__Inherit = self.Plugins[ Base ]
		Table.__InheritBlacklist = Options.BlacklistKeys
		Table.__InheritWhitelist = Options.WhitelistKeys
	end
end

function Shine:LoadExtension( Name, DontEnable )
	Name = Name:lower()

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

		--NS2:Combat, don't load irrelevant plugins. Make sure we stop before network messages.
		if self.IsNS2Combat and Plugin.NS2Only then
			self.Plugins[ Name ] = nil
			return false, "plugin not compatible with NS2:Combat"
		end

		Plugin.IsShared = true

		if Plugin.SetupDataTable then --Networked variables.
			Plugin:SetupDataTable()
			Plugin:InitDataTable( Name )
		end
	end

	--Client plugins load automatically, but enable themselves later when told to.
	if Client then
		local OldValue = Plugin
		Plugin = self.Plugins[ Name ]

		if PluginFiles[ ClientFile ] then
			include( ClientFile )
		end

		Plugin = OldValue --Just in case someone else uses Plugin as a global...

		local Plugin = self.Plugins[ Name ]

		if Plugin and self.IsNS2Combat and Plugin.NS2Only then
			self.Plugins[ Name ] = nil
			return false, "plugin not compatible with NS2:Combat"
		end

		Plugin.IsClient = true

		return true
	end

	if not PluginFiles[ ServerFile ] then
		ServerFile = StringFormat( "%s%s.lua", ExtensionPath, Name )

		if not PluginFiles[ ServerFile ] then
			local Found

			local SearchTerm = StringFormat( "/%s.lua", Name )

			--In case someone uses a different case file name to the plugin name...
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

	--Global value so that the server file has access to the same table the shared one created.
	local OldValue = Plugin

	if IsShared then
		Plugin = self.Plugins[ Name ]
	end

	include( ServerFile )

	--Clean it up afterwards ready for the next extension.
	if IsShared then
		Plugin = OldValue
	end

	local Plugin = self.Plugins[ Name ]

	if not Plugin then
		return false, "plugin did not register itself."
	end

	if self.IsNS2Combat and Plugin.NS2Only then
		self.Plugins[ Name ] = nil
		return false, "plugin not compatible with NS2:Combat"
	end

	Plugin.IsShared = IsShared and true or nil

	if DontEnable then return true end
	
	return self:EnableExtension( Name )
end

--Shared extensions need to be enabled once the server tells it to.
function Shine:EnableExtension( Name, DontLoadConfig )
	local Plugin = self.Plugins[ Name ]

	if not Plugin then
		return false, "plugin does not exist"
	end

	if Plugin.Enabled then
		self:UnloadExtension( Name )
	end

	local Conflicts = Plugin.Conflicts

	--Deal with inter-plugin conflicts.
	if Conflicts then
		local DisableThem = Conflicts.DisableThem
		local DisableUs = Conflicts.DisableUs

		if DisableUs then
			for i = 1, #DisableUs do
				local Plugin = DisableUs[ i ]

				local PluginTable = self.Plugins[ Plugin ]
				local SetToEnable = self.Config.ActiveExtensions[ Plugin ]

				--Halt our enabling, we're not allowed to load with this plugin enabled.
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

				--Don't allow them to load, or unload them if they have already.
				if SetToEnable or ( PluginTable and PluginTable.Enabled ) then
					self.Config.ActiveExtensions[ Plugin ] = false

					self:UnloadExtension( Plugin )
				end
			end
		end
	end

	if Plugin.HasConfig and not DontLoadConfig then
		Plugin:LoadConfig()
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

	Plugin.Enabled = true

	--We need to inform clients to enable the client portion.
	if Server and Plugin.IsShared and not self.GameIDs:IsEmpty() then 
		Shine.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = true }, true )
	end

	Hook.Call( "OnPluginLoad", Name, Plugin, Plugin.IsShared )

	return true
end

local function OnCleanupError( Err )
	local Trace = Traceback()

	local Locals = ToDebugString( Shine.GetLocals( 1 ) )

	Shine:DebugPrint( "Plugin cleanup error: %s.\n%s", true, Err, Trace )
	Shine:AddErrorReport( StringFormat( "Plugin cleanup error: %s.", Err ),
		"%s\nLocals:\n%s", true, Trace, Locals )
end

function Shine:UnloadExtension( Name )
	local Plugin = self.Plugins[ Name ]

	if not Plugin then return end
	if not Plugin.Enabled then return end

	Plugin.Enabled = false

	--Make sure cleanup doesn't break us by erroring.
	local Success = xpcall( Plugin.Cleanup, OnCleanupError, Plugin )
	if not Success then
		PluginMeta.Cleanup( Plugin )
	end

	if Server and Plugin.IsShared and not self.GameIDs:IsEmpty() then
		Shine.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = false }, true )
	end

	Hook.Call( "OnPluginUnload", Name, Plugin.IsShared )
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

local ClientPlugins = {}
--Store a list of all plugins in existence. When the server config loads, we use it.
local AllPlugins = {}
Shine.AllPlugins = AllPlugins

local AllPluginsArray = {}
Shine.AllPluginsArray = AllPluginsArray

local function AddToPluginsLists( Name )
	if not AllPlugins[ Name ] then
		AllPlugins[ Name ] = true
		AllPluginsArray[ #AllPluginsArray + 1 ] = Name
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
				ClientPlugins[ Name ] = "boolean" --Generate the network message.
				AddToPluginsLists( Name )
			elseif LoweredFileName == "server.lua" or LoweredFileName == "client.lua" then
				AddToPluginsLists( Name )
			end

			--Shared plugins should load into memory for network messages.
			Shine:LoadExtension( Name, true )
		end
	else
		Name = Name:gsub( "%.lua", "" )

		AddToPluginsLists( Name )
	end
end

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
elseif Client then
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

		for Plugin, Load in pairs( Shine.AutoLoadPlugins ) do
			if Load then
				Shine:EnableExtension( Plugin )
			end
		end
	end, -20 )
end
