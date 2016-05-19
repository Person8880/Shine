--[[
	Shine plugin datatables framework.

	These tables are synchronised automatically between server and relevant clients.

	Sending a value is as simple as a table assignment. For instance,

	self.dt.String = "Hello there!"
	self.dt.Int = 10
	self.dt.Float = 100.12

	and so on.

	Values are cached and only sent when changed. They are sent to new
	clients that connect too.

	It is imperative that datatables are created on the client and server,
	you cannot create them on one side then leave the other side for later.

	The game requires the same number of network messages on the client
	and server when it has finished loading.
]]

local Shine = Shine

local Floor = math.floor
local pairs = pairs
local rawset = rawset
local StringExplode = string.Explode
local tonumber = tonumber
local type = type

local RealData = {}
local Registered = {}
local DataTableMeta = {}

function DataTableMeta:__index( Key )
	if DataTableMeta[ Key ] then return DataTableMeta[ Key ] end
	if not RealData[ self ] then return nil end

	return RealData[ self ][ Key ]
end

function DataTableMeta:__SetChangeCallback( Table, Func )
	rawset( self, "__OnChange", Func )
	rawset( self, "__Host", Table )
end

if Server then
	local TypeCheckers = {
		string = function( Value )
			return type( Value ) == "string" and Value or nil
		end,
		integer = function( Value )
			Value = tonumber( Value )

			if not Value then return nil end

			return Floor( Value )
		end,
		float = tonumber,
		boolean = function( Value )
			if type( Value ) == "boolean" then
				return Value
			end

			return nil
		end,
		entityid = tonumber,
		enum = tonumber,
		vector = function( Value )
			return Value.isa and Value:isa( "Vector" ) and Value or nil
		end,
		angle = function( Value )
			return Value.isa and Value:isa( "Angles" ) and Value or nil
		end,
		time = tonumber
	}

	local function TypeCheck( Type, Value )
		return TypeCheckers[ Type ]( Value )
	end

	function DataTableMeta:__newindex( Key, Value )
		local Cached = RealData[ self ][ Key ]
		if Cached == nil or Cached == Value then return end

		Value = TypeCheck( self.__Values[ Key ], Value )
		if Value == nil then return end

		RealData[ self ][ Key ] = Value

		self:__SendChange( Key, Value )
	end

	function DataTableMeta:__SendChange( Key, Value )
		if self.__Access and self.__Access[ Key ] then
			local Clients = Shine:GetClientsWithAccess( self.__Access[ Key ] )

			for i = 1, #Clients do
				local Client = Clients[ i ]

				if Client then
					Shine.SendNetworkMessage( Client, self.__Name..Key,
						{ [ Key ] = Value }, true )
				end
			end

			return
		end

		Shine.SendNetworkMessage( self.__Name..Key, { [ Key ] = Value }, true )
	end

	function DataTableMeta:__SendAll()
		if self.__Access then
			for Key, Value in pairs( RealData[ self ] ) do
				self:__SendChange( Key, Value )
			end

			return
		end

		Shine.SendNetworkMessage( self.__Name, RealData[ self ], true )
	end

	--[[
		Creates and returns a serverside datatable object.

		This can read and write data, which will be automatically sent to relevant clients.

		Inputs: Message name, message values, default values, access requirement if applicable.
		Output: Datatable object.
	]]
	function Shine:CreateDataTable( Name, Values, Defaults, Access )
		local Register = Registered[ Name ]

		if Register then
			for Key, Value in pairs( Defaults ) do
				Register[ Key ] = Value
			end

			return Register
		end

		Shared.RegisterNetworkMessage( Name, Values )

		for Key, Type in pairs( Values ) do
			Shared.RegisterNetworkMessage( Name..Key, { [ Key ] = Type } )

			local FirstWord = StringExplode( Type, " " )[ 1 ]

			Values[ Key ] = FirstWord
		end

		local DT = {
			__Name = Name,
			__Values = Values,
			__Access = Access
		}

		RealData[ DT ] = {}

		local Data = RealData[ DT ]

		for Key, Default in pairs( Defaults ) do
			Data[ Key ] = Default
		end

		Registered[ Name ] = DT

		return setmetatable( DT, DataTableMeta )
	end

	--Obey permissions...
	Shine.Hook.Add( "ClientConfirmConnect", "DataTablesUpdate", function( Client )
		for Table, Data in pairs( RealData ) do
			if not Table.__Access then
				Shine.SendNetworkMessage( Client, Table.__Name, Data, true )
			else
				local Access = Table.__Access

				for Key, Value in pairs( Data ) do
					if not Access[ Key ] or Shine:HasAccess( Client, Access[ Key ] ) then
						Shine.SendNetworkMessage( Client, Table.__Name..Key,
							{ [ Key ] = Value }, true )
					end
				end
			end
		end
	end )

	return
end

--Refuse creation/editing keys on the client.
function DataTableMeta:__newindex( Key, Value )

end

--Process a complete network message.
function DataTableMeta:ProcessComplete( Data )
	for Key, Value in pairs( Data ) do
		RealData[ self ][ Key ] = Value
	end
end

--Processes a partial network message.
function DataTableMeta:ProcessPartial( Key, Data )
	RealData[ self ][ Key ] = Data[ Key ]

	if self.__OnChange then
		self.__OnChange( self.__Host, Key, RealData[ self ][ Key ], Data[ Key ] )
	end
end

--[[
	Creates and returns a clientside data table object.

	The client side version can only read values, it cannot write.
]]
function Shine:CreateDataTable( Name, Values, Defaults, Access )
	local Register = Registered[ Name ]

	if Register then
		for Key, Value in pairs( Defaults ) do
			if not Access[ Key ] then
				Register[ Key ] = Value
			end
		end

		return Register
	end

	Shared.RegisterNetworkMessage( Name, Values )

	local DT = {
		__Name = Name,
		__Values = Values,
		__Access = Access
	}

	RealData[ DT ] = {}

	local Data = RealData[ DT ]

	for Key, Type in pairs( Values ) do
		if not Access[ Key ] then
			Data[ Key ] = Defaults[ Key ]
		end

		local ID = Name..Key

		Shared.RegisterNetworkMessage( ID, { [ Key ] = Type } )

		Client.HookNetworkMessage( ID, function( Data )
			return DT:ProcessPartial( Key, Data )
		end )
	end

	Client.HookNetworkMessage( Name, function( Data )
		return DT:ProcessComplete( Data )
	end )

	Registered[ Name ] = DT

	return setmetatable( DT, DataTableMeta )
end
