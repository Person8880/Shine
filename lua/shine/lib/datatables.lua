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
local Hook = Shine.Hook

local Floor = math.floor
local pairs = pairs
local rawget = rawget
local rawset = rawset
local StringExplode = string.Explode
local StringFormat = string.format
local TableGetKeys = table.GetKeys
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

local function DefineDataTableEntity( Name )
	class( Name )( Entity )

	local DataTableClass = _G[ Name ]
	DataTableClass.kMapName = Name
	return DataTableClass
end

local function GetFieldNetworkMessageName( DTName, Key )
	return StringFormat( "%s/%s", DTName, Key )
end

if Server then
	local getmetatable = getmetatable

	-- These are the same, but doing it this way makes it more future proof.
	local AngleMeta = getmetatable( Angles() )
	local VectorMeta = getmetatable( Vector() )

	local TypeCheckers = {
		angle = tonumber,
		angles = function( Value )
			return getmetatable( Value ) == AngleMeta and Value:isa( "Angles" ) and Value or nil
		end,
		boolean = function( Value )
			if type( Value ) == "boolean" then
				return Value
			end

			return nil
		end,
		entityid = tonumber,
		enum = tonumber,
		float = tonumber,
		integer = function( Value )
			Value = tonumber( Value )

			if not Value then return nil end

			return Floor( Value )
		end,
		resource = tonumber,
		string = function( Value )
			return type( Value ) == "string" and Value or nil
		end,
		time = tonumber,
		vector = function( Value )
			return getmetatable( Value ) == VectorMeta and Value:isa( "Vector" ) and Value or nil
		end
	}
	TypeCheckers.position = TypeCheckers.vector

	local function TypeCheck( Type, Value )
		return TypeCheckers[ Type ]( Value )
	end

	function DataTableMeta:__newindex( Key, Value )
		local FieldType = rawget( self, "__Values" )[ Key ]
		if not FieldType then return end

		local CoercedValue = TypeCheck( FieldType, Value )
		if CoercedValue == nil then
			error( StringFormat( "Invalid value provided for datatable field %s (expected %s, got %s)",
				Key, FieldType, type( Value ) ), 2 )
		elseif CoercedValue ~= RealData[ self ][ Key ] then
			RealData[ self ][ Key ] = CoercedValue

			self:__SendChange( Key, CoercedValue )
		end
	end

	function DataTableMeta:__SendChange( Key, Value )
		local Access = rawget( self, "__Access" )
		local Name = rawget( self, "__Name" )

		local NetworkMessageName = GetFieldNetworkMessageName( Name, Key )

		if Access and Access[ Key ] then
			local Clients = Shine:GetClientsWithAccess( Access[ Key ] )

			for i = 1, #Clients do
				local Client = Clients[ i ]
				if Client then
					Shine.SendNetworkMessage( Client, NetworkMessageName, { [ Key ] = Value }, true )
				end
			end

			return
		end

		Shine.SendNetworkMessage( NetworkMessageName, { [ Key ] = Value }, true )

		-- If there's a predicted entity, update its network variable too.
		local DTEntity = rawget( self, "__Entity" )
		if DTEntity then
			DTEntity[ Key ] = Value
		end
	end

	function DataTableMeta:__SendAll()
		local Access = rawget( self, "__Access" )
		if Access then
			for Key, Value in pairs( RealData[ self ] ) do
				self:__SendChange( Key, Value )
			end
			return
		end
		Shine.SendNetworkMessage( rawget( self, "__Name" ), RealData[ self ], true )
	end

	--[[
		Creates and returns a serverside datatable object.

		This can read and write data, which will be automatically sent to relevant clients.

		Inputs: Message name, message values, default values, access requirement if applicable.
		Output: Datatable object.
	]]
	function Shine:CreateDataTable( Name, Values, Defaults, Access, Predicted )
		local Register = Registered[ Name ]

		if Register then
			for Key, Value in pairs( Defaults ) do
				Register[ Key ] = Value
			end

			return Register
		end

		Shared.RegisterNetworkMessage( Name, Values )

		local ValueTypeNames = {}
		for Key, Type in pairs( Values ) do
			local FirstWord = StringExplode( Type, " ", true )[ 1 ]
			if not TypeCheckers[ FirstWord ] then
				error( StringFormat( "Unsupported datatable variable type for key '%s': %s", Key, Type ), 2 )
			end

			ValueTypeNames[ Key ] = FirstWord

			Shared.RegisterNetworkMessage( GetFieldNetworkMessageName( Name, Key ), { [ Key ] = Type } )
		end

		local DT = {
			__Name = Name,
			__Access = Access,
			__Values = ValueTypeNames
		}
		RealData[ DT ] = {}

		local Data = RealData[ DT ]
		for Key, Default in pairs( Defaults ) do
			local FieldType = ValueTypeNames[ Key ]
			if FieldType then
				Default = TypeCheck( FieldType, Default )
				Data[ Key ] = Default
			end
		end

		if Predicted then
			-- Prediction VM can't receive network messages, it can only see entities. Thus the datatable needs to be
			-- represented by an entity as well as network messages.
			local DataTableClass = DefineDataTableEntity( Name )
			local Keys = TableGetKeys( Values )
			local Logger = Shine.Logger

			function DataTableClass:OnCreate()
				Entity.OnCreate( self )

				-- This is a global utility entity, so always network it.
				self:SetPropagate( Entity.Propagate_Always )
				self:SetUpdates( false )

				-- Initialise the datatable values on creation, future updates are handled by __newindex above.
				for i = 1, #Keys do
					local Value = Data[ Keys[ i ] ]
					if Value ~= nil then
						self[ Keys[ i ] ] = Value
					end
				end
			end

			function DataTableClass:OnDestroy()
				Logger:Warn( "Datatable entity %s is being destroyed, this will break prediction VM networking!", Name )
			end

			Shared.LinkClassToMap( Name, DataTableClass.kMapName, Values )

			Hook.Add( "MapPostLoad", function()
				local EntityName = DataTableClass.kMapName
				local DTEntity = Server.CreateEntity( EntityName )
				assert( DTEntity, "Failed to create datatable entity!" )
				rawset( DT, "__Entity", DTEntity )
			end )

			Hook.CallAfterFileLoad( "lua/NS2Gamerules.lua", function()
				-- Protect the entity from being destroyed whenever the gamerules resets the game world.
				NS2Gamerules.resetProtectedEntities[ #NS2Gamerules.resetProtectedEntities + 1 ] = Name
			end )
		end

		Registered[ Name ] = DT

		return setmetatable( DT, DataTableMeta )
	end

	-- Obey permissions...
	Hook.Add( "ClientConnect", "DataTablesUpdate", function( Client )
		for Table, Data in pairs( RealData ) do
			local Access = rawget( Table, "__Access" )
			local Name = rawget( Table, "__Name" )
			if not Access then
				Shine.SendNetworkMessage( Client, Name, Data, true )
			else
				for Key, Value in pairs( Data ) do
					if not Access[ Key ] or Shine:HasAccess( Client, Access[ Key ] ) then
						Shine.SendNetworkMessage(
							Client,
							GetFieldNetworkMessageName( Name, Key ),
							{ [ Key ] = Value },
							true
						)
					end
				end
			end
		end
	end )

	return
end

-- Refuse creation/editing keys on the client.
function DataTableMeta:__newindex( Key, Value )

end

-- Process a complete network message.
function DataTableMeta:ProcessComplete( Data )
	for Key, Value in pairs( Data ) do
		RealData[ self ][ Key ] = Value
	end
end

local function OnDataUpdated( self, Key, Value )
	local OldValue = RealData[ self ][ Key ]
	RealData[ self ][ Key ] = Value

	local OnChange = rawget( self, "__OnChange" )
	if OnChange then
		OnChange( rawget( self, "__Host" ), Key, OldValue, Value )
	end
end

-- Processes a partial network message.
function DataTableMeta:ProcessPartial( Key, Data )
	return OnDataUpdated( self, Key, Data[ Key ] )
end

--[[
	Creates and returns a clientside data table object.

	The client side version can only read values, it cannot write.
]]
function Shine:CreateDataTable( Name, Values, Defaults, Access, Predicted )
	local Register = Registered[ Name ]

	if Register then
		for Key, Value in pairs( Defaults ) do
			if not Access[ Key ] then
				Register[ Key ] = Value
			end
		end

		return Register
	end

	if not Predict then
		Shared.RegisterNetworkMessage( Name, Values )
	end

	local DT = {
		__Name = Name,
		__Values = Values,
		__Access = Access
	}

	RealData[ DT ] = {}

	local Data = RealData[ DT ]

	if Predicted then
		local DataTableClass = DefineDataTableEntity( Name )
		local Keys = TableGetKeys( Values )
		local NumKeys = #Keys

		local Logger = Shine.Logger

		function DataTableClass:OnCreate()
			Entity.OnCreate( self )

			self:SetPropagate( Entity.Propagate_Always )
			self:SetUpdates( false )

			if Predict then
				local LastSeenState = {}
				for i = 1, #Keys do
					local Key = Keys[ i ]
					LastSeenState[ Key ] = Data[ Key ]
				end

				-- Prediction VM can only "think" in OnProcessMove and doesn't fire field watcher callbacks...
				Hook.Add( "OnProcessMove", self, function()
					for i = 1, NumKeys do
						local Key = Keys[ i ]
						local LastState = LastSeenState[ Key ]
						local NewState = self[ Key ]
						if LastState ~= NewState then
							LastSeenState[ Key ] = NewState
							OnDataUpdated( DT, Key, NewState )
							Logger:Trace(
								"Datatable %s changed key '%s' from %s to %s",
								Name,
								Key,
								LastState,
								NewState
							)
						end
					end
				end )
			end
		end

		Shared.LinkClassToMap( Name, DataTableClass.kMapName, Values )
	end

	for Key, Type in pairs( Values ) do
		if not Access[ Key ] then
			Data[ Key ] = Defaults[ Key ]
		end

		if not Predict then
			local ID = GetFieldNetworkMessageName( Name, Key )

			Shared.RegisterNetworkMessage( ID, { [ Key ] = Type } )

			Shine.HookNetworkMessage( ID, function( Data )
				return DT:ProcessPartial( Key, Data )
			end )
		end
	end

	if not Predict then
		Shine.HookNetworkMessage( Name, function( Data )
			return DT:ProcessComplete( Data )
		end )
	end

	Registered[ Name ] = DT

	return setmetatable( DT, DataTableMeta )
end
