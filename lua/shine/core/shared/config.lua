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
local StringUpper = string.upper
local TableCopy = table.Copy
local TableGetField = table.GetField
local TableSetField = table.SetField
local TableToJSON = table.ToJSON
local type = type

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

function Shine.FileExists( Path )
	local Contents = {}
	Shared.GetMatchingFileNames( Path, false, Contents )
	return Contents[ 1 ] ~= nil
end

do
	local JSON = require "shine/lib/json"
	local JSONDecodeErrorHandler = Shine.BuildErrorHandler( "JSON deserialisation error" )
	local CallbackErrorHandler = Shine.BuildErrorHandler( "DecodeJSONAsync callback error" )

	--[[
		Decodes a JSON string asynchronously.

		Inputs:
			1. JSONString - the JSON string to be decoded.
			2. OnDecoded - a callback that will be called on completion with either:
				* The decoded value, or
				* nil, byte position deserialisation failed at, and a description of the error.
			3. TimeLimitInSeconds - the maximum time in seconds per tick/frame to spend decoding. By default, this is
			   10% of the tick rate on the server, and 10% of a 60FPS frame-time on the client.
	]]
	function Shine.DecodeJSONAsync( JSONString, OnDecoded, TimeLimitInSeconds )
		if not TimeLimitInSeconds then
			if Server then
				TimeLimitInSeconds = 1 / Server.GetTickrate() * 0.1
			else
				TimeLimitInSeconds = 1 / 60 * 0.1
			end
		end

		Shine.TypeCheck( JSONString, "string", 1, "DecodeJSONAsync" )
		Shine.AssertAtLevel( Shine.IsCallable( OnDecoded ), "OnDecoded callback must be callable!", 3 )
		Shine.TypeCheck( TimeLimitInSeconds, "number", 3, "DecodeJSONAsync" )

		local Clock = Shared.GetSystemTimeReal
		local Decoder = JSON.DecoderFromString( JSONString )
		local Done, Value, Pos, Err
		local Iterations = 0

		Shine.Hook.Add( "Think", Decoder, function()
			if Done then
				-- Last tick finished decoding, now call the callback (ensures the callback's time doesn't add to
				-- any time spent deserialising).
				Shine.Hook.Remove( "Think", Decoder )

				Shine.Logger:Debug(
					"Finished parsing JSON after %d iteration(s) (time limit was %s)", Iterations, TimeLimitInSeconds
				)

				xpcall( OnDecoded, CallbackErrorHandler, Value, Pos, Err )

				return
			end

			Iterations = Iterations + 1

			local Start = Clock()
			local Success
			repeat
				Success, Done, Value, Pos, Err = xpcall( Decoder, JSONDecodeErrorHandler )
			until not Success or Done or Clock() - Start >= TimeLimitInSeconds

			if not Success then
				-- Unexpected error while decoding, fallback to DKJSON.
				Shine.Hook.Remove( "Think", Decoder )
				xpcall( OnDecoded, CallbackErrorHandler, Decode( JSONString ) )
			end
		end )
	end
end

local JSONErrorHandler = Shine.BuildErrorHandler( "JSON serialisation error" )
function Shine.SaveJSONFile( Table, Path, Settings )
	Settings = Settings or JSONSettings

	local FormattingOptions = {
		PrettyPrint = Settings.indent or false,
		IndentSize = 4 * ( Settings.level or 1 )
	}
	if not FormattingOptions.PrettyPrint then
		-- No point having consistent order if not pretty printing.
		FormattingOptions.TableIterator = pairs
	end

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

--[[
	Applies a migration to the given config, modifying it in-place to match the new version based on a given list of
	migration steps.

	Inputs:
		1. The config object to migrate.
		2. Parameters providing:
			"CurrentVersion" - The current version of the given configuration object (before migration).
			"NewVersion" - a string denoting the new version of the configuration.
			"MigrationSteps" - an optional table of migration steps, each with a "VersionTo" field indicating the
			version they migrate to, and an "Apply" function that takes the config object and migrates it in-place.
]]
function Shine.ApplyConfigMigration( Config, Params )
	Config.__Version = Params.NewVersion

	if Params.MigrationSteps then
		local StartingStep
		local EndStep = #Params.MigrationSteps

		-- Find the first step that migrates to a version later than the config's current version.
		for i = 1, EndStep do
			local Step = Params.MigrationSteps[ i ]
			if Shine.VersionHolder( Step.VersionTo ) > Params.CurrentVersion then
				StartingStep = i
				break
			end
		end

		if StartingStep then
			for i = StartingStep, EndStep do
				Params.MigrationSteps[ i ].Apply( Config )
			end
		end
	end

	return Config
end

do
	local Clamp = math.Clamp
	local Floor = math.floor
	local StringExplode = string.Explode
	local StringGSub = string.gsub
	local StringMatch = string.match
	local TableBuild = table.Build
	local TableConcat = table.concat
	local TableRemove = table.remove
	local TableShallowCopy = table.ShallowCopy
	local tonumber = tonumber
	local unpack = unpack

	local Print = Print
	if Predict then
		-- Suppress output from the prediction VM to avoid double-printing.
		Print = function() end
	end

	local ValidationContext = Shine.TypeDef()
	function ValidationContext:Init( MessagePrefix, Config )
		self.Path = {}
		self.MessagePrefix = MessagePrefix
		self.Config = Config
		return self
	end

	function ValidationContext:PushField( FieldName )
		self.Path[ #self.Path + 1 ] = FieldName
	end

	function ValidationContext:PopField()
		self.Path[ #self.Path ] = nil
	end

	local function PopAfterCall( self, ... )
		self:PopField()
		return ...
	end

	function ValidationContext:WithField( FieldName, Func, ... )
		self:PushField( FieldName )
		return PopAfterCall( self, Func( ... ) )
	end

	function ValidationContext:GetCurrentPath()
		local Output = {}
		for i = 1, #self.Path do
			local Field = self.Path[ i ]
			if IsType( Field, "string" ) then
				if tonumber( Field ) then
					Output[ #Output + 1 ] = StringFormat( "[ %q ]", Field )
				else
					if i > 1 then
						Output[ #Output + 1 ] = "."
					end
					Output[ #Output + 1 ] = Field
				end
			else
				Output[ #Output + 1 ] = StringFormat( "[ %s ]", Field )
			end
		end
		return TableConcat( Output )
	end

	local Validator = {}
	Validator.__index = Validator

	function Validator.Constant( Value )
		return function() return Value end
	end

	function Validator.Integer( Rounder )
		Rounder = Rounder or Floor

		return {
			Check = function( Value )
				return ( tonumber( Value ) or 0 ) % 1 ~= 0
			end,
			Fix = function( Value )
				return Rounder( tonumber( Value ) )
			end,
			Message = function()
				return "%s must have an integer value"
			end
		}
	end

	function Validator.Min( MinValue )
		return {
			Check = function( Value )
				return ( tonumber( Value ) or 0 ) < MinValue
			end,
			Fix = Validator.Constant( MinValue ),
			Message = function()
				return StringFormat( "%%s must have a value of at least %s", MinValue )
			end
		}
	end
	function Validator.Clamp( Min, Max )
		return {
			Check = function( Value )
				return Clamp( Value, Min, Max ) ~= Value
			end,
			Fix = function( Value )
				return Clamp( Value, Min, Max )
			end,
			Message = function()
				return StringFormat( "%%s must have a value between %s and %s", Min, Max )
			end
		}
	end

	do
		local Operators = {
			GreaterThan = function( Left, Right ) return Left > Right end,
			GreaterThanOrEqualTo = function( Left, Right ) return Left >= Right end,
			LessThan = function( Left, Right ) return Left < Right end,
			LessThanOrEqualTo = function( Left, Right ) return Left <= Right end,
			EqualTo = function( Left, Right ) return Left == Right end,
			NotEqualTo = function( Left, Right ) return Left ~= Right end
		}
		for Name, Operator in pairs( Operators ) do
			local NiceName = {}
			for Word in Name:gmatch( "%u%U+" ) do
				NiceName[ #NiceName + 1 ] = Word:lower()
			end

			NiceName = TableConcat( NiceName, " " )

			Validator[ Name.."Field" ] = function( FieldName, FixFunc )
				local NiceFieldName = IsType( FieldName, "table" ) and TableConcat( FieldName, "." ) or FieldName
				return {
					Check = function( Value, Context )
						local Right = TableGetField( Context.Config, FieldName )
						return not Operator( Value, Right )
					end,
					Fix = function( Value, Context )
						return FixFunc( Value, TableGetField( Context.Config, FieldName ) )
					end,
					Message = function()
						return StringFormat( "%%s must have a value that is %s %s", NiceName, NiceFieldName )
					end
				}
			end
		end
	end

	function Validator.MatchesPattern( Pattern, DefaultValue )
		Shine.TypeCheck( Pattern, "string", 1, "MatchesPattern" )

		return {
			Check = function( Value )
				return not IsType( Value, "string" ) or not StringMatch( Value, Pattern )
			end,
			Fix = Validator.Constant( DefaultValue ),
			Message = function()
				return StringFormat( "%%s must match pattern %s", ( StringGSub( Pattern, "%%", "%%%%" ) ) )
			end
		}
	end

	function Validator.HasLength( ExpectedLength, DefaultElement )
		return {
			Check = function( Value )
				return not IsType( Value, "table" ) or #Value ~= ExpectedLength
			end,
			Fix = function( Value )
				if not IsType( Value, "table" ) then
					return nil
				end

				if #Value > ExpectedLength then
					for i = ExpectedLength + 1, #Value do
						Value[ i ] = nil
					end
				else
					for i = #Value + 1, ExpectedLength do
						Value[ i ] = DefaultElement
					end
				end

				return Value
			end,
			Message = function()
				return StringFormat( "%%s must have %d element%s", ExpectedLength, ExpectedLength == 1 and "" or "s" )
			end
		}
	end

	function Validator.ValidateField( Name, Rule, Options )
		Shine.TypeCheck( Rule, "table", 2, "ValidateField" )
		Shine.TypeCheck( Options, { "table", "nil" }, 3, "ValidateField" )

		local FixFunc = Rule.Fix
		local MessageFunc = Rule.Message
		local Predicate = Rule.Check
		local DeleteIfFieldInvalid = Options and Options.DeleteIfFieldInvalid

		return {
			Check = function( Value, Context )
				if not IsType( Value, "table" ) then return true end

				local NeedsFix, CanonicalValue = Context:WithField( Name, Predicate, Value[ Name ], Context )
				if not NeedsFix and CanonicalValue ~= nil then
					local Copy = TableShallowCopy( Value )
					Copy[ Name ] = CanonicalValue
					CanonicalValue = Copy
				end

				return NeedsFix, CanonicalValue
			end,
			Fix = function( Value, Context )
				if not IsType( Value, "table" ) then
					local Fixed = Context:WithField( Name, FixFunc, nil, Context )
					if Fixed ~= nil then
						return {
							[ Name ] = Fixed
						}
					end
					return nil
				end

				local FixedValue = Context:WithField( Name, FixFunc, Value[ Name ], Context )
				if FixedValue == nil and DeleteIfFieldInvalid then
					return nil
				end

				Value[ Name ] = FixedValue

				return Value
			end,
			Message = function()
				return StringFormat( "%s on field %s", MessageFunc(), Name )
			end
		}
	end

	function Validator.InEnum( PossibleValues, DefaultValue )
		return {
			Check = function( Value )
				if not IsType( Value, "string" ) or PossibleValues[ StringUpper( Value ) ] == nil then
					return true
				end
				return false, StringUpper( Value )
			end,
			Fix = Validator.Constant( DefaultValue ),
			Message = function()
				return StringFormat(
					"%%s must equal one of [\"%s\"]", Shine.Stream( PossibleValues ):Concat( "\", \"" )
				)
			end
		}
	end

	function Validator.Each( Predicate, FixFunc, MessageFunc )
		if IsType( Predicate, "table" ) then
			FixFunc = Predicate.Fix
			MessageFunc = Predicate.Message
			Predicate = Predicate.Check
		end

		return {
			Check = function( Value, Context )
				local Passes = true
				for i = 1, #Value do
					Context:PushField( i )

					local NeedsFix, CanonicalValue = Predicate( Value[ i ], Context )
					if NeedsFix then
						Print( Context.MessagePrefix..MessageFunc(), Context:GetCurrentPath() )
						Passes = false
					elseif CanonicalValue ~= nil then
						Value[ i ] = CanonicalValue
					end

					Context:PopField()
				end
				return not Passes
			end,
			Fix = function( Value, Context )
				for i = #Value, 1, -1 do
					Context:PushField( i )

					if Predicate( Value[ i ], Context ) then
						local Fixed = FixFunc( Value[ i ], Context )
						if Fixed ~= nil then
							Value[ i ] = Fixed
						else
							TableRemove( Value, i )
						end
					end

					Context:PopField()
				end
				return Value
			end,
			Message = function()
				return "Elements of "..MessageFunc()
			end
		}
	end

	function Validator.EachKeyValue( Rule )
		Shine.TypeCheck( Rule, "table", 2, "EachKeyValue" )

		local FixFunc = Rule.Fix
		local MessageFunc = Rule.Message
		local Predicate = Rule.Check

		return {
			Check = function( TableValue, Context )
				local Passes = true

				for Key, Value in pairs( TableValue ) do
					Context:PushField( Key )

					local NeedsFix, CanonicalValue = Predicate( Value, Context )
					if NeedsFix then
						Print( Context.MessagePrefix..MessageFunc(), Context:GetCurrentPath() )
						Passes = false
					elseif CanonicalValue ~= nil then
						TableValue[ Key ] = CanonicalValue
					end

					Context:PopField()
				end

				return not Passes
			end,
			Fix = function( TableValue, Context )
				for Key, Value in pairs( TableValue ) do
					Context:PushField( Key )

					if Predicate( Value, Context ) then
						local Fixed = FixFunc( Value, Context )
						if Fixed ~= nil then
							TableValue[ Key ] = Fixed
						else
							TableValue[ Key ] = nil
						end
					end

					Context:PopField()
				end

				return TableValue
			end,
			Message = function()
				return "Elements of "..MessageFunc()
			end
		}
	end

	function Validator.AllValuesSatisfy( ... )
		local Rules = { ... }

		for i = 1, #Rules do
			Rules[ i ] = Validator.Each( Rules[ i ] )
		end

		return unpack( Rules )
	end

	function Validator.AllKeyValuesSatisfy( ... )
		local Rules = { ... }

		for i = 1, #Rules do
			Rules[ i ] = Validator.EachKeyValue( Rules[ i ] )
		end

		return unpack( Rules )
	end

	function Validator.IsType( Type, DefaultValue )
		return {
			Check = function( Value )
				return not IsType( Value, Type )
			end,
			Fix = Validator.Constant( DefaultValue ),
			Message = function()
				return StringFormat( "%%s must have type %s", Type )
			end
		}
	end

	function Validator.IsAnyType( Types, DefaultValue )
		return {
			Check = function( Value )
				for i = 1, #Types do
					if IsType( Value, Types[ i ] ) then
						return false
					end
				end
				return true
			end,
			Fix = Validator.Constant( DefaultValue ),
			Message = function()
				return StringFormat( "%%s must have type %s", TableConcat( Types, " or " ) )
			end
		}
	end

	-- If the value is of the given type, then it will be validated with the given predicate(s).
	function Validator.IfType( Type, ... )
		local Rules = { ... }
		if IsType( Rules[ 1 ], "function" ) then
			-- Backwards compatibility.
			Rules = {
				{
					Check = Rules[ 1 ],
					Fix = Rules[ 2 ],
					Message = Rules[ 3 ]
				}
			}
		end

		for i = 1, #Rules do
			local Rule = Rules[ i ]
			Rules[ i ] = {
				Check = function( Value, Context )
					if not IsType( Value, Type ) then
						return false
					end
					return Rule.Check( Value, Context )
				end,
				Fix = Rule.Fix,
				Message = Rule.Message
			}
		end

		return unpack( Rules )
	end

	function Validator.IfFieldPresent( Field, ... )
		local Rules = { ... }

		for i = 1, #Rules do
			local Rule = Rules[ i ]
			Rules[ i ] = {
				Check = function( Value, Context )
					if Value[ Field ] == nil then
						return false
					end
					return Rule.Check( Value, Context )
				end,
				Fix = Rule.Fix,
				Message = Rule.Message
			}
		end

		return unpack( Rules )
	end

	function Validator.Exclusive( FieldA, FieldB, Options )
		return {
			Check = function( Value, Context )
				if Value[ FieldA ] ~= nil and Value[ FieldB ] ~= nil then
					return true
				end

				if Options and Options.FailIfBothMissing and Value[ FieldA ] == nil and Value[ FieldB ] == nil then
					return true
				end

				return false
			end,
			Fix = function( Value )
				if Options then
					if
						Options.DeleteIfInvalid
						or ( Options.FailIfBothMissing and Value[ FieldA ] == nil and Value[ FieldB ] == nil )
					then
						return nil
					end

					if Options.FieldToKeep == FieldA then
						Value[ FieldB ] = nil
						return Value
					end
				end

				Value[ FieldA ] = nil

				return Value
			end,
			Message = function()
				return StringFormat( "%%s must specify only one of %s or %s", FieldA, FieldB )
			end
		}
	end

	function Validator:AddRule( Rule )
		self.Rules[ #self.Rules + 1 ] = Rule
	end

	function Validator:CheckTypesAgainstDefault( Field, DefaultConfigSegment )
		for Key, Value in pairs( DefaultConfigSegment ) do
			self:AddFieldRule( StringFormat( "%s.%s", Field, Key ), self.IsType( type( Value ), Value ) )
		end
	end

	function Validator:AddFieldRule( Field, ... )
		self.FieldRules = self.FieldRules or {}
		self.FieldRules[ Field ] = true

		local Checks = { ... }
		if IsType( Checks[ 1 ], "function" ) then
			-- Backwards compatibility.
			Checks = {
				{
					Check = Checks[ 1 ],
					Fix = Checks[ 2 ],
					Message = Checks[ 3 ]
				}
			}
		end

		for i = 1, #Checks do
			local CheckPredicate = Checks[ i ].Check
			local FixFunction = Checks[ i ].Fix
			local MessageSupplier = Checks[ i ].Message
			self:AddRule( {
				Matches = function( Rule, Config, Context )
					local TableField = type( Field ) == "string" and Field or Field[ 1 ]
					local PrintField = type( Field ) == "string" and Field or Field[ 2 ]

					Context:PushField( PrintField )

					local Path = StringExplode( TableField, ".", true )
					local Value = TableGetField( Config, Path )
					local NeedsFix, CanonicalValue = CheckPredicate( Value, Context )
					if NeedsFix then
						if MessageSupplier then
							Print( self.MessagePrefix..MessageSupplier(), PrintField )
						end

						TableSetField( Config, Path, FixFunction( Value, Context ) )

						Context:PopField()

						return true
					end

					Context:PopField()

					if CanonicalValue ~= nil then
						TableSetField( Config, Path, CanonicalValue )
					end

					return false
				end
			} )
		end
	end

	function Validator:AddFieldRules( Fields, ... )
		for i = 1, #Fields do
			self:AddFieldRule( Fields[ i ], ... )
		end
	end

	function Validator:HasFieldRule( Field )
		return self.FieldRules and self.FieldRules[ Field ]
	end

	function Validator:Add( OtherValidator )
		for i = 1, #OtherValidator.Rules do
			self:AddRule( OtherValidator.Rules[ i ] )
		end
	end

	function Validator:Validate( Config )
		local ChangesMade = false
		local Context = ValidationContext( self.MessagePrefix, Config )

		for i = 1, #self.Rules do
			local Rule = self.Rules[ i ]

			if Rule:Matches( Config, Context ) then
				ChangesMade = true
				if Rule.Fix then
					Rule:Fix( Config, Context )
				end
			end
		end

		return ChangesMade
	end

	function Shine.Validator( MessagePrefix )
		return setmetatable( { Rules = {}, MessagePrefix = MessagePrefix or "" }, Validator )
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

	function Migrator:AddField( FieldName, Value )
		self.Actions[ #self.Actions + 1 ] = function( Config )
			local ValueToSet
			if IsType( Value, "function" ) then
				ValueToSet = Value( Config )
			else
				ValueToSet = Value
			end
			TableSetField( Config, FieldName, ValueToSet )
		end
		return self
	end

	function Migrator:RenameField( FromName, ToName )
		self.Actions[ #self.Actions + 1 ] = function( Config )
			local OldValue = TableGetField( Config, FromName )
			TableSetField( Config, ToName, OldValue )
			TableSetField( Config, FromName, nil )
		end
		return self
	end

	function Migrator:CopyField( FromName, ToName )
		self.Actions[ #self.Actions + 1 ] = function( Config )
			local OldValue = TableGetField( Config, FromName )
			if IsType( OldValue, "table" ) then
				-- Avoid copying by reference so later actions don't mutate both the old and new field.
				OldValue = TableCopy( OldValue )
			end
			TableSetField( Config, ToName, OldValue )
		end
		return self
	end

	function Migrator:RemoveField( FieldName )
		self.Actions[ #self.Actions + 1 ] = function( Config )
			TableSetField( Config, FieldName, nil )
		end
		return self
	end

	function Migrator:MapField( FieldName, Mapper )
		Shine.AssertAtLevel( Shine.IsCallable( Mapper ), "Mapper must be callable!", 3 )

		self.Actions[ #self.Actions + 1 ] = function( Config )
			local Value = TableGetField( Config, FieldName )
			TableSetField( Config, FieldName, Mapper( Value ) )
		end

		return self
	end

	function Migrator:RenameEnum( FieldName, From, To )
		return self:MapField( FieldName, function( Value )
			if IsType( Value, "string" ) and StringUpper( Value ) == From then
				return To
			end
			return Value
		end )
	end

	function Migrator:RenameEnums( FieldNames, From, To )
		for i = 1, #FieldNames do
			self:RenameEnum( FieldNames[ i ], From, To )
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
