--[[
	Networking module.
]]

local Shine = Shine

local pairs = pairs
local rawget = rawget
local StringFormat = string.format

local NetworkingModule = {}

--[[
	Adds a variable to the plugin's data table.

	Inputs:
		Type - The network variable's type, e.g "string (128)".
		Name - The name on the data table to give this variable.
		Default - The default value.
		Access - Optional access string, if set,
		only clients with access to this will receive this variable.
]]
function NetworkingModule:AddDTVar( Type, Name, Default, Access )
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
function NetworkingModule:InitDataTable( Name )
	if not self.DTVars then return end

	self.dt = Shine:CreateDataTable( "Shine_DT_"..Name, self.DTVars.Keys,
		self.DTVars.Defaults, self.DTVars.Access )

	if self.NetworkUpdate then
		self.dt:__SetChangeCallback( self, self:WrapCallback( self.NetworkUpdate ) )
	end

	self.DTVars = nil
end

do
	local function GetReceiverName( Name )
		return StringFormat( "Receive%s", Name )
	end

	local NetworkReceiveError = Shine.BuildErrorHandler( "Plugin network receiver error" )
	local xpcall = xpcall

	--[[
		Adds a network message to the plugin.

		Calls Plugin:Receive<Name>( Client, Data ) if receiving on the server side,
		or Plugin:Receive<Name>( Data ) if receiving on the client side.

		Call this function inside shared.lua -> Plugin:SetupDataTable().
	]]
	function NetworkingModule:AddNetworkMessage( Name, Params, Receiver )
		self.__NetworkMessages = rawget( self, "__NetworkMessages" ) or {}

		Shine.Assert( not self.__NetworkMessages[ Name ],
			"Attempted to register network message %s for plugin %s twice!", Name, self.__Name )

		local MessageName = StringFormat( "SH_%s_%s", self.__Name, Name )
		local FuncName = GetReceiverName( Name )

		self.__NetworkMessages[ Name ] = MessageName

		Shared.RegisterNetworkMessage( MessageName, Params )

		local function CallReceiver( ... )
			if not self[ FuncName ] then
				-- Report better errors than "attempt to call a nil value"
				error( StringFormat( "Plugin %s defined network message %s, but no receiver!", self.__Name, Name ), 0 )
			end

			self[ FuncName ]( ... )
		end

		if Receiver == "Server" and Server then
			Server.HookNetworkMessage( MessageName, function( Client, Data )
				xpcall( CallReceiver, NetworkReceiveError, self, Client, Data )
			end )
		elseif Receiver == "Client" and Client then
			Client.HookNetworkMessage( MessageName, function( Data )
				xpcall( CallReceiver, NetworkReceiveError, self, Data )
			end )
		end
	end

	function NetworkingModule:GetNameNetworkField()
		local NameLength = kMaxNameLength * 4 + 1
		return StringFormat( "string (%i)", NameLength )
	end

	function NetworkingModule:AddNetworkMessageHandler( Name, Params, Handler )
		self:AddNetworkMessage( Name, Params, "Client" )

		if not Client then return end

		local FuncName = GetReceiverName( Name )
		if self[ FuncName ] then return end

		self[ FuncName ] = Handler
	end

	local function GetMessageTranslationKey( Name, VariationKey, Data )
		local Key = Name
		if VariationKey then
			Key = StringFormat( "%s_%s", Key, Data[ VariationKey ] )
		end
		return Key
	end

	function NetworkingModule:AddTranslatedMessage( Name, Params, VariationKey )
		Params.AdminName = self:GetNameNetworkField()

		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			self:CommandNotify( Data.AdminName, GetMessageTranslationKey( Name, VariationKey, Data ), Data )
		end )
	end

	function NetworkingModule:AddTranslatedNotify( Name, Params, VariationKey )
		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			self:Notify( self:GetInterpolatedPhrase( GetMessageTranslationKey( Name, VariationKey, Data ), Data ) )
		end )
	end

	function NetworkingModule:AddTranslatedNotifyColour( Name, Params, VariationKey )
		Params.R = "integer (0 to 255)"
		Params.G = Params.R
		Params.B = Params.R

		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			local Key = GetMessageTranslationKey( Name, VariationKey, Data )
			self:NotifySingleColour( Data.R, Data.G, Data.B, self:GetInterpolatedPhrase( Key, Data ) )
		end )
	end

	function NetworkingModule:AddTranslatedError( Name, Params, VariationKey )
		self:AddNetworkMessageHandler( Name, Params, function( self, Data )
			local Key = GetMessageTranslationKey( Name, VariationKey, Data )
			self:NotifyError( self:GetInterpolatedPhrase( Key, Data ) )
		end )
	end

	function NetworkingModule:AddTranslatedCommandError( Name, Params )
		Shine.RegisterTranslatedCommandError( Name, Params, self.__Name )
	end

	function NetworkingModule:AddNetworkMessages( Method, Messages, ... )
		for Type, Names in pairs( Messages ) do
			for i = 1, #Names do
				self[ Method ]( self, Names[ i ], Type, ... )
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
	function NetworkingModule:SendNetworkMessage( Target, Name, Data, Reliable )
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
	function NetworkingModule:SendTranslatedMessage( Client, Name, Params )
		Shine:DoCommandNotify( Client, Params or {}, SendTranslatedCommandNotify, self, Name )
	end

	function NetworkingModule:SendTranslatedNotify( Target, Name, Params )
		self:SendNetworkMessage( Target, Name, Params or {}, true )
	end

	NetworkingModule.SendTranslatedError = NetworkingModule.SendTranslatedNotify
	NetworkingModule.SendTranslatedNotifyColour = NetworkingModule.SendTranslatedNotify

	function NetworkingModule:SendTranslatedCommandError( Target, Name, Params )
		Shine:SendTranslatedCommandError( Target, Name, Params, self.__Name )
	end
else
	function NetworkingModule:SendNetworkMessage( Name, Data, Reliable )
		local MessageName = self.__NetworkMessages[ Name ]
		if not MessageName then
			error( StringFormat( "Attempted to send unregistered network message '%s' for plugin '%s'.",
				Name, self.__Name ), 2 )
		end

		Shine.SendNetworkMessage( MessageName, Data, Reliable )
	end
end

Shine.BasePlugin:AddModule( NetworkingModule )
