--[[
	Shared config stuff.
]]

local Encode, Decode = json.encode, json.decode
local getmetatable = getmetatable
local Open = io.open
local pairs = pairs
local xpcall = xpcall
local setmetatable = setmetatable
local StringFormat = string.format
local TableToJSON = table.ToJSON
local type = type

-- Make JSON encoding always have consistent order.
Shine.SetUpValue( Encode, "pairs", SortedPairs, true )

local JSONSettings = { indent = true, level = 1 }

local IsType = Shine.IsType

local function ReadFile( Path )
	local File, Err = Open( Path, "r" )
	if not File then
		return nil, Err
	end

	local Contents = File:read( "*all" )
	File:close()

	return Contents
end
Shine.ReadFile = ReadFile

local function WriteFile( Path, Contents )
	local File, Err = Open( Path, "w+" )

	if not File then
		return nil, Err
	end

	File:write( Contents )
	File:close()

	return true
end
Shine.WriteFile = WriteFile

function Shine.LoadJSONFile( Path )
	local Data, Err = ReadFile( Path )
	if not Data then
		return false, Err
	end

	return Decode( Data )
end

local JSONErrorHandler = Shine.BuildErrorHandler( "JSON serialisation error" )
function Shine.SaveJSONFile( Table, Path, Settings )
	Settings = Settings or JSONSettings
	local FormattingOptions = {
		PrettyPrint = Settings.indent or false,
		IndentSize = 4 * ( Settings.level or 1 )
	}
	local Success, JSON = xpcall( TableToJSON, JSONErrorHandler, Table, FormattingOptions )
	if not Success then
		-- Fallback to DKJSON if there's somehow a bug in our serialiser.
		JSON = Encode( Table, Settings )
	end
	return WriteFile( Path, JSON )
end

-- Checks a config for missing entries including the first level of sub-tables.
function Shine.RecursiveCheckConfig( Config, DefaultConfig, DontRemove )
	local Updated

	-- Add new keys.
	for Option, Value in pairs( DefaultConfig ) do
		if Config[ Option ] == nil then
			Config[ Option ] = Value

			Updated = true
		elseif IsType( Value, "table" ) then
			for Index, Val in pairs( Value ) do
				if Config[ Option ][ Index ] == nil then
					Config[ Option ][ Index ] = Val

					Updated = true
				end
			end
		end
	end

	if DontRemove then return Updated end

	-- Remove old keys.
	for Option, Value in pairs( Config ) do
		if DefaultConfig[ Option ] == nil then
			Config[ Option ] = nil

			Updated = true
		elseif IsType( Value, "table" ) then
			for Index, Val in pairs( Value ) do
				if DefaultConfig[ Option ][ Index ] == nil then
					Config[ Option ][ Index ] = nil

					Updated = true
				end
			end
		end
	end

	return Updated
end

do
	local IgnorableValue = {}
	--[[
		Marks a table value as ignorable when checking configuration
		values.

		This should be used when a table does not have fixed keys. It will not change
		the table's behaviour at all, it just adds a marker meta-table.
	]]
	function Shine.IgnoreWhenChecking( Value )
		Shine.TypeCheck( Value, "table", 1, "IgnoreWhenChecking" )
		return setmetatable( Value, IgnorableValue )
	end

	local function ShouldIgnore( DefaultValue )
		return getmetatable( DefaultValue ) == IgnorableValue
	end

	--[[
		For each value in the configuration recursively, ensure that any missing
		keys in the provided config are added, and that any keys not present in the
		default config are removed.

		This ignores any key that is a number on the basis that it's likely an array
		value and thus it is not useful to check.

		Tables can also be set to be ignored manually by using Shine.IgnoreWhenChecking().
	]]
	function Shine.VerifyConfig( Config, DefaultConfig, ReservedKeys )
		local Updated = false

		for Option, DefaultValue in pairs( DefaultConfig ) do
			-- Ignore any number keys, assume they are default array options which can vary.
			if not IsType( Option, "number" ) then
				local ProvidedValue = Config[ Option ]
				-- If no value has been provided for this key, add it.
				if ProvidedValue == nil then
					Config[ Option ] = DefaultValue
					Updated = true
				-- If the default value is a table, check its keys as long as it's not set
				-- to be ignored in the default config.
				elseif IsType( DefaultValue, "table" ) and IsType( ProvidedValue, "table" )
				and not ShouldIgnore( DefaultValue ) then
					Updated = Shine.VerifyConfig( ProvidedValue, DefaultValue ) or Updated
				end
			end
		end

		for Option, Value in pairs( Config ) do
			-- If the value no longer exists in the default config, and it's not
			-- an array value or reserved key, remove it.
			if DefaultConfig[ Option ] == nil
			and not ( ReservedKeys and ReservedKeys[ Option ] )
			and not IsType( Option, "number" ) then
				Config[ Option ] = nil
				Updated = true
			end
		end

		return Updated
	end
end

-- Checks a config for missing entries without checking sub-tables.
function Shine.CheckConfig( Config, DefaultConfig, DontRemove, ReservedKeys )
	local Updated

	-- Add new keys.
	for Option, Value in pairs( DefaultConfig ) do
		if Config[ Option ] == nil then
			Config[ Option ] = Value

			Updated = true
		end
	end

	if DontRemove then return Updated end

	-- Remove old keys.
	for Option, Value in pairs( Config ) do
		if DefaultConfig[ Option ] == nil
		and not ( ReservedKeys and ReservedKeys[ Option ] ) then
			Config[ Option ] = nil

			Updated = true
		end
	end

	return Updated
end

function Shine.TypeCheckConfig( Name, Config, DefaultConfig, Recursive )
	local Edited

	for Key, Value in pairs( Config ) do
		if DefaultConfig[ Key ] ~= nil then
			local ExpectedType = type( DefaultConfig[ Key ] )
			local RealType = type( Value )

			if ExpectedType ~= RealType then
				Print( "Type mis-match in %s config for key '%s', expected type: '%s', got type '%s'. Reverting value to default.",
					Name, Key, ExpectedType, RealType )

				Config[ Key ] = DefaultConfig[ Key ]
				Edited = true
			end

			if Recursive and ExpectedType == "table" then
				local SubEdited = Shine.TypeCheckConfig( StringFormat( "%s.%s", Name, Key ),
					Value, DefaultConfig[ Key ], Recursive )
				Edited = Edited or SubEdited
			end
		end
	end

	return Edited
end

do
	local Clamp = math.Clamp
	local Floor = math.floor
	local StringExplode = string.Explode
	local StringUpper = string.upper
	local TableBuild = table.Build
	local TableConcat = table.concat
	local TableRemove = table.remove
	local tonumber = tonumber
	local unpack = unpack

	local Validator = {}
	Validator.__index = Validator

	function Validator.Constant( Value )
		return function() return Value end
	end

	function Validator.Integer( Rounder )
		Rounder = Rounder or Floor

		return function( Value )
			return ( tonumber( Value ) or 0 ) % 1 ~= 0
		end,
		function( Value )
			return Rounder( tonumber( Value ) )
		end,
		function()
			return "%s must be an integer"
		end
	end

	function Validator.Min( MinValue )
		return function( Value )
			return ( tonumber( Value ) or 0 ) < MinValue
		end,
		Validator.Constant( MinValue ),
		function()
			return StringFormat( "%%s must be at least %s", MinValue )
		end
	end
	function Validator.Clamp( Min, Max )
		return function( Value )
			return Clamp( Value, Min, Max ) ~= Value
		end,
		function( Value )
			return Clamp( Value, Min, Max )
		end,
		function()
			return StringFormat( "%%s must be between %s and %s", Min, Max )
		end
	end

	function Validator.ValidateField( Name, Predicate, FixFunc, MessageFunc )
		return function( Value )
			if not IsType( Value, "table" ) then return true end
			return Predicate( Value[ Name ] )
		end,
		function( Value )
			if not IsType( Value, "table" ) then
				local Fixed = FixFunc( nil )
				if Fixed ~= nil then
					return {
						[ Name ] = Fixed
					}
				end
				return nil
			end

			Value[ Name ] = FixFunc( Value[ Name ] )

			return Value
		end,
		function()
			return StringFormat( "Field %s on %s", Name, MessageFunc() )
		end
	end

	function Validator.InEnum( PossibleValues, DefaultValue )
		return function( Value )
			if not IsType( Value, "string" ) or PossibleValues[ StringUpper( Value ) ] == nil then
				return true
			end
			return false, StringUpper( Value )
		end,
		Validator.Constant( DefaultValue ),
		function()
			return StringFormat( "%%s must be one of [%s]", Shine.Stream( PossibleValues ):Concat( ", " ) )
		end
	end

	function Validator.Each( Predicate, FixFunc, MessageFunc )
		return function( Value )
			local Passes = true
			for i = 1, #Value do
				local NeedsFix, CanonicalValue = Predicate( Value[ i ] )
				if NeedsFix then
					Passes = false
				elseif CanonicalValue ~= nil then
					Value[ i ] = CanonicalValue
				end
			end
			return not Passes
		end,
		function( Value )
			for i = #Value, 1, -1 do
				if Predicate( Value[ i ] ) then
					local Fixed = FixFunc( Value[ i ] )
					if Fixed ~= nil then
						Value[ i ] = Fixed
					else
						TableRemove( Value, i )
					end
				end
			end
			return Value
		end,
		function()
			return "Elements of "..MessageFunc()
		end
	end

	function Validator.IsType( Type, DefaultValue )
		return function( Value )
			return not IsType( Value, Type )
		end,
		Validator.Constant( DefaultValue ),
		function()
			return StringFormat( "%%s must be a %s", Type )
		end
	end

	function Validator.IsAnyType( Types, DefaultValue )
		return function( Value )
			for i = 1, #Types do
				if IsType( Value, Types[ i ] ) then
					return false
				end
			end
			return true
		end,
		Validator.Constant( DefaultValue ),
		function()
			return StringFormat( "%%s must have type %s", TableConcat( Types, " or " ) )
		end
	end

	-- If the value is of the given type, then it will be validated with the given predicate.
	function Validator.IfType( Type, CheckPredicate, FixFunction, MessageSupplier )
		return function( Value )
			if not IsType( Value, Type ) then
				return false
			end
			return CheckPredicate( Value )
		end, FixFunction, MessageSupplier
	end

	function Validator:AddRule( Rule )
		self.Rules[ #self.Rules + 1 ] = Rule
	end

	local function SetField( Root, Path, Value )
		local Table = TableBuild( Root, unpack( Path, 1, #Path - 1 ) )
		Table[ Path[ #Path ] ] = Value
	end

	function Validator:AddFieldRule( Field, CheckPredicate, FixFunction, MessageSupplier )
		self:AddRule( {
			Matches = function( self, Config )
				local TableField = type( Field ) == "string" and Field or Field[ 1 ]
				local PrintField = type( Field ) == "string" and Field or Field[ 2 ]

				local Path = StringExplode( TableField, "%." )
				local Value = Config
				for i = 1, #Path do
					Value = Value[ Path[ i ] ]
					if Value == nil then break end
				end

				local NeedsFix, CanonicalValue = CheckPredicate( Value )
				if NeedsFix then
					if MessageSupplier then
						Print( MessageSupplier(), PrintField )
					end

					SetField( Config, Path, FixFunction( Value ) )
					return true
				end

				if CanonicalValue ~= nil then
					SetField( Config, Path, CanonicalValue )
				end

				return false
			end
		} )
	end
	function Validator:AddFieldRules( Fields, CheckPredicate, FixFunction, MessageSupplier )
		for i = 1, #Fields do
			self:AddFieldRule( Fields[ i ], CheckPredicate, FixFunction, MessageSupplier )
		end
	end

	function Validator:Add( OtherValidator )
		for i = 1, #OtherValidator.Rules do
			self:AddRule( OtherValidator.Rules[ i ] )
		end
	end

	function Validator:Validate( Config )
		local ChangesMade = false

		for i = 1, #self.Rules do
			local Rule = self.Rules[ i ]

			if Rule:Matches( Config ) then
				ChangesMade = true
				if Rule.Fix then
					Rule:Fix( Config )
				end
			end
		end

		return ChangesMade
	end

	function Shine.Validator()
		return setmetatable( { Rules = {} }, Validator )
	end
end

do
	-- Small helper for common config migration tasks.
	local Migrator = Shine.TypeDef()
	Migrator.__call = function( self, Config )
		for i = 1, #self.Actions do
			self.Actions[ i ]( Config )
		end
		return Config
	end

	function Migrator:Init()
		self.Actions = {}
		return self
	end

	function Migrator:RenameField( FromName, ToName )
		self.Actions[ #self.Actions + 1 ] = function( Config )
			local OldValue = Config[ FromName ]
			Config[ ToName ] = OldValue
			Config[ FromName ] = nil
		end
		return self
	end

	function Migrator:UseEnum( FieldWithNumber, EnumValues )
		self.Actions[ #self.Actions + 1 ] = function( Config )
			Config[ FieldWithNumber ] = EnumValues[ Config[ FieldWithNumber ] ]
		end
		return self
	end

	function Migrator:ApplyAction( Action )
		self.Actions[ #self.Actions + 1 ] = Action
		return self
	end

	Shine.Migrator = Migrator
end
