--[[
	Base plugin metatable.
]]

local Shine = Shine

local IsType = Shine.IsType
local Notify = Shared.Message
local pairs = pairs
local rawget = rawget
local setmetatable = setmetatable
local StringFormat = string.format
local type = type

local function Print( ... )
	return Notify( StringFormat( ... ) )
end

local ClientConfigPath = "config://shine/cl_plugins/"

local PluginMeta = {}
Shine.BasePlugin = PluginMeta

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
		Access - Optional access string, if set,
		only clients with access to this will receive this variable.
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
	
	self.dt = Shine:CreateDataTable( "Shine_DT_"..Name, self.DTVars.Keys,
		self.DTVars.Defaults, self.DTVars.Access )

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
		local Path = Server and Shine.Config.ExtensionDir..self.ConfigName
			or ClientConfigPath..self.ConfigName

		local Success, Err = Shine.SaveJSONFile( self.Config, Path )

		if not Success then
			Print( "Error writing %s config file: %s", self.__Name, Err )	

			return	
		end

		Print( "Shine %s config file created.", self.__Name )
	end
end

function PluginMeta:SaveConfig( Silent )
	local Path = Server and ( rawget( self, "__ConfigPath" )
		or Shine.Config.ExtensionDir..self.ConfigName ) or ClientConfigPath..self.ConfigName

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
	local Path = Server and Shine.Config.ExtensionDir..self.ConfigName
		or ClientConfigPath..self.ConfigName

	local Err
	local Pos

	if Server then
		local Gamemode = Shine.GetGamemode()

		--Look for gamemode specific config file.
		if Gamemode ~= Shine.BaseGamemode then
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
			for Key, Command in pairs( self.Commands ) do
				Shine:RemoveCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ Key ] = nil
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
			for Key, Command in pairs( self.Commands ) do
				Shine:RemoveClientCommand( Command.ConCmd, Command.ChatCmd )
				self.Commands[ Key ] = nil
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
		for Key, Command in pairs( self.Commands ) do
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
		for Key, Command in pairs( self.Commands ) do
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
