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
	Shine.TypeCheck( Type, "string", 1, "AddDTVar" )
	Shine.TypeCheck( Name, "string", 2, "AddDTVar" )
	if Access ~= nil then
		Shine.TypeCheck( Access, "string", 4, "AddDTVar" )
	end

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

do
	local function GetReceiverName( Name )
		return StringFormat( "Receive%s", Name )
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
		local FuncName = GetReceiverName( Name )

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

	function PluginMeta:GetNameNetworkField()
		local NameLength = kMaxNameLength * 4 + 1
		return StringFormat( "string (%i)", NameLength )
	end

	function PluginMeta:AddNetworkMessageHandler( Name, Params, Handler )
		self:AddNetworkMessage( Name, Params, "Client" )

		if not Client then return end

		local FuncName = GetReceiverName( Name )
		if self[ FuncName ] then return end

		self[ FuncName ] = Handler
	end

	function PluginMeta:AddTranslatedMessage( Name, Params )
		Params.AdminName = self:GetNameNetworkField()

		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			self:CommandNotify( Data.AdminName, Name, Data )
		end )
	end

	function PluginMeta:AddTranslatedNotify( Name, Params )
		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			self:Notify( self:GetInterpolatedPhrase( Name, Data ) )
		end )
	end

	function PluginMeta:AddTranslatedNotifyColour( Name, Params )
		Params.R = "integer (0 to 255)"
		Params.G = Params.R
		Params.B = Params.R

		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			self:NotifySingleColour( Data.R, Data.G, Data.B, self:GetInterpolatedPhrase( Name, Data ) )
		end )
	end

	function PluginMeta:AddTranslatedError( Name, Params )
		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			self:NotifyError( self:GetInterpolatedPhrase( Name, Data ) )
		end )
	end

	function PluginMeta:AddTranslatedCommandError( Name, Params )
		Shine.RegisterTranslatedCommandError( Name, Params, self.__Name )
	end

	function PluginMeta:AddNetworkMessages( Method, Messages )
		for Type, Names in pairs( Messages ) do
			for i = 1, #Names do
				self[ Method ]( self, Names[ i ], Type )
			end
		end
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
		if not MessageName then
			error( StringFormat( "Attempted to send unregistered network message '%s' for plugin '%s'.",
				Name, self.__Name ), 2 )
		end

		Shine:ApplyNetworkMessage( Target, MessageName, Data, Reliable )
	end

	local function SendTranslatedCommandNotify( Shine, Target, Name, Message, Plugin, MessageName )
		Message.AdminName = Name
		Plugin:SendNetworkMessage( Target, MessageName, Message, true )
	end

	--[[
		Sends a translated command notification.
	]]
	function PluginMeta:SendTranslatedMessage( Client, Name, Params )
		Shine:DoCommandNotify( Client, Params or {}, SendTranslatedCommandNotify, self, Name )
	end

	function PluginMeta:SendTranslatedNotify( Target, Name, Params )
		self:SendNetworkMessage( Target, Name, Params or {}, true )
	end

	PluginMeta.SendTranslatedError = PluginMeta.SendTranslatedNotify
	PluginMeta.SendTranslatedNotifyColour = PluginMeta.SendTranslatedNotify

	function PluginMeta:SendTranslatedCommandError( Target, Name, Params )
		Shine:SendTranslatedCommandError( Target, Name, Params, self.__Name )
	end
elseif Client then
	function PluginMeta:SendNetworkMessage( Name, Data, Reliable )
		local MessageName = self.__NetworkMessages[ Name ]
		if not MessageName then
			error( StringFormat( "Attempted to send unregistered network message '%s' for plugin '%s'.",
				Name, self.__Name ), 2 )
		end

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
			Print( "Invalid JSON for %s plugin config. Error: %s. Loading default...", self.__Name, Err )

			self.Config = self.DefaultConfig
		end

		return
	end

	self.Config = PluginConfig

	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function( _, Config )
			return self.CheckConfig and Shine.CheckConfig( Config, self.DefaultConfig )
		end
	} )
	Validator:AddRule( {
		Matches = function( _, Config )
			return self.CheckConfigTypes and self:TypeCheckConfig()
		end
	} )

	if Validator:Validate( self.Config ) then
		self:SaveConfig()
	end
end

function PluginMeta:TypeCheckConfig()
	return Shine.TypeCheckConfig( self.__Name, self.Config, self.DefaultConfig )
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

	function PluginMeta:AddAdminMenuCommand( Category, Name, Command, MultiSelect, DoClick, Tooltip )
		self.AdminMenuCommands = rawget( self, "AdminMenuCommands" ) or {}
		self.AdminMenuCommands[ Category ] = true

		Shine.AdminMenu:AddCommand( Category, Name, Command, MultiSelect, DoClick, Tooltip )
	end

	function PluginMeta:AddAdminMenuTab( Name, Data )
		self.AdminMenuTabs = rawget( self, "AdminMenuTabs" ) or {}
		self.AdminMenuTabs[ Name ] = true

		Shine.AdminMenu:AddTab( Name, Data )
	end

	function PluginMeta:GetPhrase( Key )
		local Phrase = Shine.Locale:GetPhrase( self.__Name, Key )

		if self.__Inherit and Phrase == Key then
			return self.__Inherit:GetPhrase( Key )
		end

		if Phrase == Key then
			return Shine.Locale:GetPhrase( "Core", Key )
		end

		return Phrase
	end

	function PluginMeta:GetInterpolatedPhrase( Key, FormatArgs )
		local Phrase = Shine.Locale:GetInterpolatedPhrase( self.__Name, Key, FormatArgs )

		if self.__Inherit and Phrase == Key then
			return self.__Inherit:GetInterpolatedPhrase( Key, FormatArgs )
		end

		if Phrase == Key then
			return Shine.Locale:GetInterpolatedPhrase( "Core", Key, FormatArgs )
		end

		return Phrase
	end

	function PluginMeta:AddChatLine( RP, GP, BP, Prefix, R, G, B, Message )
		Shine.AddChatText( RP, GP, BP, Prefix, R / 255, G / 255, B / 255, Message )
	end

	function PluginMeta:CommandNotify( AdminName, MessageKey, Data )
		self:AddChatLine( 255, 255, 0, AdminName,
			255, 255, 255, self:GetInterpolatedPhrase( MessageKey, Data ) )
	end

	function PluginMeta:Notify( Message )
		local PrefixCol = self.NotifyPrefixColour

		self:AddChatLine( PrefixCol[ 1 ], PrefixCol[ 2 ], PrefixCol[ 3 ], self:GetPhrase( "NOTIFY_PREFIX" ),
			255, 255, 255, Message )
	end

	function PluginMeta:NotifySingleColour( R, G, B, Message )
		self:AddChatLine( 0, 0, 0, "", R, G, B, Message )
	end

	function PluginMeta:NotifyError( Message )
		Shine:NotifyError( Message )
	end

	do
		local StringExplode = string.Explode
		local StringFind = string.find
		local TimeToString = string.TimeToString
		local Transformers = string.InterpolateTransformers

		-- Transforms a boolean into one of two strings.
		Transformers.BoolToPhrase = function( FormatArg, TransformArg )
			local Args = StringExplode( TransformArg, "|" )
			return FormatArg and Args[ 1 ] or Args[ 2 ]
		end

		-- Transforms a team number into a team name using Shine:GetTeamName().
		Transformers.TeamName = function( FormatArg, TransformArg )
			return Shine:GetTeamName( FormatArg,
				StringFind( TransformArg, "capitals" ) ~= nil,
				StringFind( TransformArg, "singular" ) ~= nil )
		end

		-- Transforms a number into a phrase, if the number is 1, then the first, otherwise the second.
		Transformers.Pluralise = function( FormatArg, TransformArg )
			local Args = StringExplode( TransformArg, "|" )
			return FormatArg == 1 and Args[ 1 ] or Args[ 2 ]
		end

		-- Transforms a time value into a string duration. Optionally, a translation key for 0 can be given.
		Transformers.Duration = function( FormatArg, TransformArg )
			if FormatArg == 0 and TransformArg and TransformArg ~= "" then
				return Shine.Locale:GetPhrase( "Core", TransformArg )
			end

			return TimeToString( FormatArg )
		end

		-- Adds the argument only if the value is non-zero.
		Transformers.NonZero = function( FormatArg, TransformArg )
			return FormatArg == 0 and "" or TransformArg
		end

		-- Adds one of two values depending on if the value is negative or not.
		Transformers.Sign = function( FormatArg, TransformArg )
			local Args = StringExplode( TransformArg, "|" )
			return FormatArg < 0 and Args[ 1 ] or Args[ 2 ]
		end

		-- Gets a translation value from a given source.
		Transformers.Translation = function( FormatArg, TransformArg )
			local Source = TransformArg or "Core"
			return Shine.Locale:GetPhrase( Source, FormatArg )
		end
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
	Shine.TypeCheck( Delay, "number", 2, "CreateTimer" )
	Shine.TypeCheck( Reps, "number", 3, "CreateTimer" )
	Shine.TypeCheck( Func, "function", 4, "CreateTimer" )

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
	Shine.TypeCheck( Delay, "number", 1, "SimpleTimer" )
	Shine.TypeCheck( Func, "function", 2, "SimpleTimer" )

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

--Provides an easy way to delay actions in think-esque hooks.
function PluginMeta:CanRunAction( Action, Time, Delay )
	self.TimedActions = rawget( self, "TimedActions" ) or {}

	if ( self.TimedActions[ Action ] or 0 ) > Time then return false end

	self.TimedActions[ Action ] = Time + Delay

	return true
end

if Server then
	local function GetName( self )
		return rawget( self, "PrintName" ) or self.__Name
	end

	function PluginMeta:Print( Message, Format, ... )
		Shine:Print( "[%s] %s", true, GetName( self ),
			Format and StringFormat( Message, ... ) or Message )
	end

	function PluginMeta:Notify( Player, Message, Format, ... )
		Shine.TypeCheck( Message, "string", 2, "Notify" )

		local NotifyColour = self.NotifyPrefixColour

		Shine:NotifyDualColour( Player, NotifyColour[ 1 ], NotifyColour[ 2 ], NotifyColour[ 3 ],
			StringFormat( "[%s]", GetName( self ) ), 255, 255, 255, Message, Format, ... )
	end

	function PluginMeta:NotifyTranslated( Player, Message )
		local NotifyColour = self.NotifyPrefixColour

		Shine:TranslatedNotifyDualColour( Player, NotifyColour[ 1 ], NotifyColour[ 2 ], NotifyColour[ 3 ],
			"NOTIFY_PREFIX", 255, 255, 255, Message, self.__Name )
	end

	function PluginMeta:NotifyTranslatedError( Player, Message )
		Shine:TranslatedNotifyError( Player, Message, self.__Name )
	end

	function PluginMeta:NotifyTranslatedCommandError( Player, Message )
		Shine:TranslatedNotifyCommandError( Player, Message, self.__Name )
	end
end

local ReservedKeys = {
	Enabled = true,
	Suspended = true
}
--Support plugins inheriting from other plugins.
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
