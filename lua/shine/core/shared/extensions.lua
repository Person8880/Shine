--[[
	Shine extension system.

	Supports server side, client side and shared plugins.
]]

local include = Script.Load
local next = next
local pairs = pairs
local Notify = Shared.Message
local pcall = pcall
local rawget = rawget
local setmetatable = setmetatable
local StringExplode = string.Explode
local StringFormat = string.format
local type = type

local function Print( ... )
	return Notify( StringFormat( ... ) )
end

local Hook = Shine.Hook

local IsType = Shine.IsType

Shine.Plugins = {}

local AutoLoadPath = "config://shine/AutoLoad.json"
local ClientConfigPath = "config://shine/cl_plugins/"
local ExtensionPath = "lua/shine/extensions/"

--Here we collect every extension file so we can be sure it exists before attempting to load it.
local Files = {}
Shared.GetMatchingFileNames( ExtensionPath.."*.lua", true, Files )
local PluginFiles = {}

--Convert to faster table.
for i = 1, #Files do
	PluginFiles[ Files[ i ] ] = true
end

local PluginMeta = {}

--[[
	Base initialise, just enables the plugin, nothing more.
	Override to add to it.
]]
function PluginMeta:Initialise()
	self.Enabled = true

	return true
end

--[[
	Adds a variable to the plugin's data table.

	Inputs:
		Type - The network variable's type, e.g "string (128)".
		Name - The name on the data table to give this variable.
		Default - The default value.
		Access - Optional access string, if set, only clients with access to this will receive this variable.
]]
function PluginMeta:AddDTVar( Type, Name, Default, Access )
	self.DTVars = self.DTVars or {}
	self.DTVars.Keys = self.DTVars.Keys or {}
	self.DTVars.Defaults = self.DTVars.Defaults or {}
	self.DTVars.Access = self.DTVars.Access or {}

	self.DTVars.Keys[ Name ] = Type
	self.DTVars.Defaults[ Name ] = Default
	self.DTVars.Access[ Name ] = Access
end

--[[
	Do not call directly, this is used to finalise the data table after setup.
]]
function PluginMeta:InitDataTable( Name )
	if not self.DTVars then return end
	
	self.dt = Shine:CreateDataTable( "Shine_DT_"..Name, self.DTVars.Keys, self.DTVars.Defaults, self.DTVars.Access )

	if self.NetworkUpdate then
		self.dt:__SetChangeCallback( self, self.NetworkUpdate )
	end

	self.DTVars = nil
end

--[[
	Adds a network message to the plugin.

	Calls Plugin:Receive<Name>( Client, Data ) if receiving on the server side,
	or Plugin:Receive<Name>( Data ) if receiving on the client side.

	Call this function inside shared.lua -> Plugin:SetupDataTable().
]]
function PluginMeta:AddNetworkMessage( Name, Params, Receiver )
	self.__NetworkMessages = rawget( self, "__NetworkMessages" ) or {}

	Shine.Assert( not self.__NetworkMessages[ Name ], 
		"Attempted to register network message %s for plugin %s twice!", Name, self.__Name )

	local MessageName = StringFormat( "SH_%s_%s", self.__Name, Name )
	local FuncName = StringFormat( "Receive%s", Name )

	self.__NetworkMessages[ Name ] = MessageName

	Shared.RegisterNetworkMessage( MessageName, Params )

	if Receiver == "Server" and Server then
		Server.HookNetworkMessage( MessageName, function( Client, Data )
			self[ FuncName ]( self, Client, Data )
		end )
	elseif Receiver == "Client" and Client then
		Client.HookNetworkMessage( MessageName, function( Data )
			self[ FuncName ]( self, Data )
		end )
	end
end

if Server then
	--[[
		Sends an internal plugin network message.

		Inputs:
			Name - Message name that was registered.
			Targets - Table of clients, a single client, or nil to send to everyone.
			Data - Message data.
			Reliable - Boolean whether to ensure the message reaches its target(s).
	]]
	function PluginMeta:SendNetworkMessage( Target, Name, Data, Reliable )
		local MessageName = self.__NetworkMessages[ Name ]

		if IsType( Target, "table" ) then
			for i = 1, #Target do
				local Client = Target[ i ]

				if Client then
					Shine.SendNetworkMessage( Client, MessageName, Data, Reliable )
				end
			end
		elseif Target then
			Shine.SendNetworkMessage( Target, MessageName, Data, Reliable )
		else
			Shine.SendNetworkMessage( MessageName, Data, Reliable )
		end
	end
elseif Client then
	function PluginMeta:SendNetworkMessage( Name, Data, Reliable )
		local MessageName = self.__NetworkMessages[ Name ]

		Shine.SendNetworkMessage( MessageName, Data, Reliable )
	end
end

function PluginMeta:GenerateDefaultConfig( Save )
	self.Config = self.DefaultConfig

	if Save then
		local Path = Server and Shine.Config.ExtensionDir..self.ConfigName or ClientConfigPath..self.ConfigName

		local Success, Err = Shine.SaveJSONFile( self.Config, Path )

		if not Success then
			Print( "Error writing %s config file: %s", self.__Name, Err )	

			return	
		end

		Print( "Shine %s config file created.", self.__Name )
	end
end

function PluginMeta:SaveConfig( Silent )
	local Path = Server and ( rawget( self, "__ConfigPath" ) or Shine.Config.ExtensionDir..self.ConfigName ) or ClientConfigPath..self.ConfigName

	local Success, Err = Shine.SaveJSONFile( self.Config, Path )

	if not Success then
		Print( "Error writing %s config file: %s", self.__Name, Err )	

		return
	end

	if not self.SilentConfigSave and not Silent then
		Print( "Shine %s config file updated.", self.__Name )
	end
end

function PluginMeta:LoadConfig()
	local PluginConfig
	local Path = Server and Shine.Config.ExtensionDir..self.ConfigName or ClientConfigPath..self.ConfigName

	local Err
	local Pos

	if Server then
		local Gamemode = Shine.GetGamemode()

		--Look for gamemode specific config file.
		if Gamemode ~= "ns2" then
			local Paths = {
				StringFormat( "%s%s/%s", Shine.Config.ExtensionDir, Gamemode, self.ConfigName ),
				Path
			}

			for i = 1, #Paths do
				local File, ErrPos, ErrString = Shine.LoadJSONFile( Paths[ i ] )

				if File then
					PluginConfig = File

					self.__ConfigPath = Paths[ i ]

					break
				elseif IsType( ErrPos, "number" ) then
					Err = ErrString
					Pos = ErrPos
				end
			end
		else
			PluginConfig, Pos, Err = Shine.LoadJSONFile( Path )
		end
	else
		PluginConfig, Pos, Err = Shine.LoadJSONFile( Path )
	end

	if not PluginConfig or not IsType( PluginConfig, "table" ) then
		if IsType( Pos, "string" ) then
			self:GenerateDefaultConfig( true )
		else
			Print( "Invalid JSON for %s plugin config, loading default...", self.__Name )

			self.Config = self.DefaultConfig
		end

		return
	end

	self.Config = PluginConfig

	local NeedsSave

	if self.CheckConfig and Shine.CheckConfig( self.Config, self.DefaultConfig ) then
		NeedsSave = true
	end

	if self.CheckConfigTypes and self:TypeCheckConfig() then
		NeedsSave = true
	end

	if NeedsSave then
		self:SaveConfig()
	end
end

function PluginMeta:TypeCheckConfig()
	local Config = self.Config
	local DefaultConfig = self.DefaultConfig

	local Edited

	for Key, Value in pairs( Config ) do
		local ExpectedType = type( DefaultConfig[ Key ] )
		local RealType = type( Value )

		if ExpectedType ~= RealType then
			Print( "Type mis-match in %s config for key '%s', expected type: '%s'. Reverting value to default.",
				self.__Name, Key, ExpectedType )

			Config[ Key ] = DefaultConfig[ Key ]
			Edited = true
		end
	end

	return Edited
end

if Server then
	--[[
		Bind a command to the plugin.
		If you call the base class Cleanup, the command will be removed on plugin unload.
	]]
	function PluginMeta:BindCommand( ConCommand, ChatCommand, Func, NoPerm, Silent )
		self.Commands = rawget( self, "Commands" ) or {}

		local Command  = Shine:RegisterCommand( ConCommand, ChatCommand, Func, NoPerm, Silent )

		self.Commands[ ConCommand ] = Command

		return Command
	end

	--[[
		Default cleanup will remove any bound commands.
		Override to add/change behaviour, call it with self.BaseClass.Cleanup( self ).
	]]
	function PluginMeta:Cleanup()
		if rawget( self, "Commands" ) then
			for k, Command in pairs( self.Commands ) do
				Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ k ] = nil
			end
		end

		self:DestroyAllTimers()
	end
elseif Client then
	function PluginMeta:BindCommand( ConCommand, Func )
		self.Commands = rawget( self, "Commands" ) or {}

		local Command = Shine:RegisterClientCommand( ConCommand, Func )

		self.Commands[ ConCommand ] = Command

		return Command
	end

	function PluginMeta:AddAdminMenuCommand( Category, Name, Command, MultiSelect, DoClick )
		self.AdminMenuCommands = rawget( self, "AdminMenuCommands" ) or {}
		self.AdminMenuCommands[ Category ] = true

		Shine.AdminMenu:AddCommand( Category, Name, Command, MultiSelect, DoClick )
	end

	function PluginMeta:AddAdminMenuTab( Name, Data )
		self.AdminMenuTabs = rawget( self, "AdminMenuTabs" ) or {}
		self.AdminMenuTabs[ Name ] = true

		Shine.AdminMenu:AddTab( Name, Data )
	end

	function PluginMeta:Cleanup()
		if rawget( self, "Commands" ) then
			for k, Command in pairs( self.Commands ) do
				Shine:RemoveClientCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ k ] = nil
			end
		end

		self:DestroyAllTimers()

		if rawget( self, "AdminMenuCommands" ) then
			for Category in pairs( self.AdminMenuCommands ) do
				Shine.AdminMenu:RemoveCommandCategory( Category )
			end
		end

		if rawget( self, "AdminMenuTabs" ) then
			for Tab in pairs( self.AdminMenuTabs ) do
				Shine.AdminMenu:RemoveTab( Tab )
			end
		end
	end
end

--[[
	Creates a timer and adds it to the list of timers associated to the plugin.
	These timers are removed when the plugin unloads in the base Cleanup method.

	Inputs: Same as Shine.Timer.Create.
]]
function PluginMeta:CreateTimer( Name, Delay, Reps, Func )
	self.Timers = rawget( self, "Timers" ) or setmetatable( {}, { __mode = "v" } )

	local RealName = StringFormat( "%s_%s", self.__Name, Name )
	local Timer = Shine.Timer.Create( RealName, Delay, Reps, Func )

	self.Timers[ Name ] = Timer

	return Timer
end

--[[
	Creates a simple timer and adds it to the list of timers associated to the plugin.
	Inputs: Same as Shine.Timer.Simple.
]]
function PluginMeta:SimpleTimer( Delay, Func )
	self.Timers = rawget( self, "Timers" ) or setmetatable( {}, { __mode = "v" } )

	local Timer = Shine.Timer.Simple( Delay, Func )

	self.Timers[ Timer.Name ] = Timer

	return Timer
end

function PluginMeta:GetTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return nil end

	return self.Timers[ Name ]
end

function PluginMeta:GetTimers()
	return rawget( self, "Timers" )
end

function PluginMeta:TimerExists( Name )
	return Shine.Timer.Exists( StringFormat( "%s_%s", self.__Name, Name ) )
end

function PluginMeta:PauseTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return end
	
	self.Timers[ Name ]:Pause()
end

function PluginMeta:ResumeTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return end
	
	self.Timers[ Name ]:Resume()
end

function PluginMeta:DestroyTimer( Name )
	if not rawget( self, "Timers" ) or not self.Timers[ Name ] then return end
	
	self.Timers[ Name ]:Destroy()

	self.Timers[ Name ] = nil
end

function PluginMeta:DestroyAllTimers()
	if rawget( self, "Timers" ) then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Destroy()
			self.Timers[ Name ] = nil
		end
	end
end

--Suspends the plugin, stopping its hooks, pausing its timers, but not calling Cleanup().
function PluginMeta:Suspend()
	if self.OnSuspend then
		self:OnSuspend()
	end
	
	if rawget( self, "Timers" ) then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Pause()
		end
	end

	if rawget( self, "Commands" ) then
		for k, Command in pairs( self.Commands ) do
			Command.Disabled = true
		end
	end

	self.Enabled = false
	self.Suspended = true
end

--Resumes the plugin from suspension.
function PluginMeta:Resume()
	if rawget( self, "Timers" ) then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Resume()
		end
	end

	if rawget( self, "Commands" ) then
		for k, Command in pairs( self.Commands ) do
			Command.Disabled = nil
		end
	end

	self.Enabled = true
	self.Suspended = nil

	if self.OnResume then
		self:OnResume()
	end
end

--Support plugins inheriting from other plugins.
function PluginMeta:__index( Key )
	if PluginMeta[ Key ] then return PluginMeta[ Key ] end

	local Inherit = rawget( self, "__Inherit" )

	if Inherit then
		local InheritBlacklist = rawget( self, "__InheritBlacklist" )
		local InheritWhitelist = rawget( self, "__InheritWhitelist" )

		if not InheritBlacklist and not InheritWhitelist then
			return Inherit[ Key ]
		end

		if InheritBlacklist and InheritBlacklist[ Key ] then return nil end
		if InheritWhitelist and not InheritWhitelist[ Key ] then return nil end

		return Inherit[ Key ]
	end
end

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
	
	local IsShared = PluginFiles[ ClientFile ] and PluginFiles[ SharedFile ] or PluginFiles[ ServerFile ]

	if PluginFiles[ SharedFile ] then
		include( SharedFile )

		local Plugin = self.Plugins[ Name ]

		if not Plugin then
			return false, "plugin did not register itself"
		end

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
		Plugin.Enabled = false

		return false, StringFormat( "Lua error: %s", Loaded )
	end

	--The plugin has refused to load.
	if not Loaded then
		return false, Err
	end

	if Server and Plugin.IsShared and next( self.GameIDs ) then --We need to inform clients to enable the client portion.
		Shine.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = true }, true )
	end

	Hook.Call( "OnPluginLoad", Name, Plugin, Plugin.IsShared )

	return true
end

function Shine:UnloadExtension( Name )
	local Plugin = self.Plugins[ Name ]

	if not Plugin then return end

	Plugin:Cleanup()

	Plugin.Enabled = false

	if Server and Plugin.IsShared and next( self.GameIDs ) then
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
--Store a list of all plugins in existance. When the server config loads, we use it.
Shine.AllPlugins = {}

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
				Shine.AllPlugins[ Name ] = true
			elseif LoweredFileName == "server.lua" then
				Shine.AllPlugins[ Name ] = true
			end

			Shine:LoadExtension( Name, true ) --Shared plugins should load into memory for network messages.
		end
	else
		Shine.AllPlugins[ Name:gsub( "%.lua", "" ) ] = true
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
