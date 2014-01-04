--[[
	Shine extension system.

	Supports server side, client side and shared plugins.
]]

local include = Script.Load
local next = next
local pairs = pairs
local Notify = Shared.Message
local setmetatable = setmetatable
local StringExplode = string.Explode
local StringFormat = string.format

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
PluginMeta.__index = PluginMeta

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
	self.__NetworkMessages = self.__NetworkMessages or {}

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
					Server.SendNetworkMessage( Client, MessageName, Data, Reliable )
				end
			end
		elseif Target then
			Server.SendNetworkMessage( Target, MessageName, Data, Reliable )
		else
			Server.SendNetworkMessage( MessageName, Data, Reliable )
		end
	end
elseif Client then
	function PluginMeta:SendNetworkMessage( Name, Data, Reliable )
		local MessageName = self.__NetworkMessages[ Name ]

		Client.SendNetworkMessage( MessageName, Data, Reliable )
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
	local Path = Server and Shine.Config.ExtensionDir..self.ConfigName or ClientConfigPath..self.ConfigName

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

	if Server then
		local Gamemode = Shine.GetGamemode()

		--Look for gamemode specific config file.
		if Gamemode ~= "ns2" then
			local GamemodePath = StringFormat( "%s%s/%s", Shine.Config.ExtensionDir, Gamemode, self.ConfigName )

			PluginConfig = Shine.LoadJSONFile( GamemodePath ) or Shine.LoadJSONFile( Path )
		else
			PluginConfig = Shine.LoadJSONFile( Path )
		end
	else
		PluginConfig = Shine.LoadJSONFile( Path )
	end

	if not PluginConfig then
		self:GenerateDefaultConfig( true )

		return
	end

	self.Config = PluginConfig

	if self.CheckConfig and Shine.CheckConfig( self.Config, self.DefaultConfig ) then 
		self:SaveConfig() 
	end
end

if Server then
	--[[
		Bind a command to the plugin.
		If you call the base class Cleanup, the command will be removed on plugin unload.
	]]
	function PluginMeta:BindCommand( ConCommand, ChatCommand, Func, NoPerm, Silent )
		self.Commands = self.Commands or {}

		local Command  = Shine:RegisterCommand( ConCommand, ChatCommand, Func, NoPerm, Silent )

		self.Commands[ ConCommand ] = Command

		return Command
	end

	--[[
		Default cleanup will remove any bound commands.
		Override to add/change behaviour, call it with self.BaseClass.Cleanup( self ).
	]]
	function PluginMeta:Cleanup()
		if self.Commands then
			for k, Command in pairs( self.Commands ) do
				Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ k ] = nil
			end
		end

		self:DestroyAllTimers()
	end
elseif Client then
	function PluginMeta:BindCommand( ConCommand, Func )
		self.Commands = self.Commands or {}

		local Command = Shine:RegisterClientCommand( ConCommand, Func )

		self.Commands[ ConCommand ] = Command

		return Command
	end

	function PluginMeta:Cleanup()
		if self.Commands then
			for k, Command in pairs( self.Commands ) do
				Shine:RemoveClientCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ k ] = nil
			end
		end

		self:DestroyAllTimers()
	end
end

--[[
	Creates a timer and adds it to the list of timers associated to the plugin.
	These timers are removed when the plugin unloads in the base Cleanup method.

	Inputs: Same as Shine.Timer.Create.
]]
function PluginMeta:CreateTimer( Name, Delay, Reps, Func )
	self.Timers = self.Timers or setmetatable( {}, { __mode = "v" } )

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
	self.Timers = self.Timers or setmetatable( {}, { __mode = "v" } )

	local Timer = Shine.Timer.Simple( Delay, Func )

	self.Timers[ Timer.Name ] = Timer

	return Timer
end

function PluginMeta:TimerExists( Name )
	return Shine.Timer.Exists( StringFormat( "%s_%s", self.__Name, Name ) )
end

function PluginMeta:PauseTimer( Name )
	if not self.Timers or not self.Timers[ Name ] then return end
	
	self.Timers[ Name ]:Pause()
end

function PluginMeta:ResumeTimer( Name )
	if not self.Timers or not self.Timers[ Name ] then return end
	
	self.Timers[ Name ]:Resume()
end

function PluginMeta:DestroyTimer( Name )
	if not self.Timers or not self.Timers[ Name ] then return end
	
	self.Timers[ Name ]:Destroy()

	self.Timers[ Name ] = nil
end

function PluginMeta:DestroyAllTimers()
	if self.Timers then
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
	
	if self.Timers then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Pause()
		end
	end

	if self.Commands then
		for k, Command in pairs( self.Commands ) do
			Command.Disabled = true
		end
	end

	self.Enabled = false
	self.Suspended = true
end

--Resumes the plugin from suspension.
function PluginMeta:Resume()
	if self.Timers then
		for Name, Timer in pairs( self.Timers ) do
			Timer:Resume()
		end
	end

	if self.Commands then
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

function Shine:RegisterExtension( Name, Table )
	self.Plugins[ Name ] = setmetatable( Table, PluginMeta )

	Table.BaseClass = PluginMeta
	Table.__Name = Name
end

function Shine:LoadExtension( Name, DontEnable )
	Name = Name:lower()

	if self.Plugins[ Name ] then return end

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

	if Server and Plugin.IsShared and next( self.GameIDs ) then --We need to inform clients to enable the client portion.
		Server.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = true }, true )
	end

	return Plugin:Initialise()
end

function Shine:UnloadExtension( Name )
	local Plugin = self.Plugins[ Name ]

	if not Plugin then return end

	Plugin:Cleanup()

	Plugin.Enabled = false

	if Server and Plugin.IsShared and next( self.GameIDs ) then
		Server.SendNetworkMessage( "Shine_PluginEnable", { Plugin = Name, Enabled = false }, true )
	end

	Hook.Call( "OnPluginUnload", Name )
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

		Server.SendNetworkMessage( Client, "Shine_PluginSync", Message, true )
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
