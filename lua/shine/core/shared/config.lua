--[[
	Shared config stuff.
]]

local Encode, Decode = json.encode, json.decode
local Open = io.open
local pairs = pairs
local StringFormat = string.format
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

function Shine.SaveJSONFile( Table, Path, Settings )
	return WriteFile( Path, Encode( Table, Settings or JSONSettings ) )
end

--Checks a config for missing entries including the first level of sub-tables.
function Shine.RecursiveCheckConfig( Config, DefaultConfig, DontRemove )
	local Updated

	--Add new keys.
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

	--Remove old keys.
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

--Checks a config for missing entries without checking sub-tables.
function Shine.CheckConfig( Config, DefaultConfig, DontRemove, ReservedKeys )
	local Updated

	--Add new keys.
	for Option, Value in pairs( DefaultConfig ) do
		if Config[ Option ] == nil then
			Config[ Option ] = Value

			Updated = true
		end
	end

	if DontRemove then return Updated end

	--Remove old keys.
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
	local StringExplode = string.Explode
	local TableBuild = table.Build
	local tonumber = tonumber
	local unpack = unpack

	local Validator = {}
	Validator.__index = Validator

	function Validator.Constant( Value )
		return function() return Value end
	end

	function Validator.Min( MinValue )
		return function( Value )
			return ( tonumber( Value ) or 0 ) < MinValue
		end, Validator.Constant( MinValue )
	end
	function Validator.Clamp( Min, Max )
		return function( Value )
			return Clamp( Value, Min, Max ) ~= Value
		end, function( Value )
			return Clamp( Value, Min, Max )
		end
	end

	function Validator:AddRule( Rule )
		self.Rules[ #self.Rules + 1 ] = Rule
	end

	function Validator:AddFieldRule( Field, CheckPredicate, FixFunction )
		self:AddRule( {
			Matches = function( self, Config )
				local Path = StringExplode( Field, "%." )
				local Value = Config
				for i = 1, #Path do
					Value = Value[ Path[ i ] ]
					if Value == nil then break end
				end

				if CheckPredicate( Value ) then
					local Table = TableBuild( Config, unpack( Path, 1, #Path - 1 ) )
					Table[ Path[ #Path ] ] = FixFunction( Value )
					return true
				end

				return false
			end
		} )
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
