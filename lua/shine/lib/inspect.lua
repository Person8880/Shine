--[[
	Inspection helpers to aid debugging.
]]

local DebugGetInfo = debug.getinfo
local getmetatable = getmetatable
local IsType = Shine.IsType
local pcall = pcall
local StringFind = string.find
local StringFormat = string.format
local StringStartsWith = string.StartsWith
local tostring = tostring
local type = type

local function GetClassName( Value )
	if Value.GetClassName then
		return StringFormat( "%s (%s)", Value, Value:GetClassName() )
	end
end

local function SafeToString( Value )
	-- __tostring() metamethods can throw errors. Unfortunately there's no rawtostring().
	local Success, String = pcall( tostring, Value )
	if not Success then
		return "error calling tostring()"
	end
	return String
end

local FFILoaded, FFI = pcall( require, "ffi" )
local FFIIsType = FFILoaded and FFI and FFI.istype or function() return false end

local Inspect = {}
local ToStringByType = {
	string = function( Value )
		if StringFind( Value, "\n", 1, true ) then
			return StringFormat( "[==[%s]==]", Value )
		end
		return StringFormat( "%q", Value )
	end,
	[ "function" ] = function( Value )
		local Source = DebugGetInfo( Value, "S" )
		return StringFormat( "%s (%s:%d)", Value, Source.short_src, Source.linedefined )
	end,
	userdata = function( Value )
		local Meta = getmetatable( Value )
		if IsType( Meta, "table" ) and Meta.__towatch then
			return SafeToString( Meta.__towatch( Value ) )
		end

		-- Some userdata may error for unknown keys.
		local Success, Name = pcall( GetClassName, Value )
		if Success and Name then
			return Name
		end

		return SafeToString( Value )
	end,
	cdata = function( Value )
		-- Hack to detect ctypes, which pass the istype call...
		if not StringStartsWith( SafeToString( Value ), "ctype<" ) then
			local Success, IsType = pcall( FFIIsType, "Color", Value )
			if Success and IsType then
				return StringFormat( "Colour( %s, %s, %s, %s )", Value.r, Value.g, Value.b, Value.a )
			end

			Success, IsType = pcall( FFIIsType, "Vector", Value )
			if Success and IsType then
				return StringFormat( "Vector( %s, %s, %s )", Value.x, Value.y, Value.z )
			end
		end

		return SafeToString( Value )
	end
}

local ToShortStringByType = table.ShallowMerge( ToStringByType, {
	table = function( Value )
		local Meta = getmetatable( Value )
		if IsType( Meta, "table" ) and Meta.__tostring and Meta.__PrintAsString then
			return SafeToString( Value )
		end
		return StringFormat( "%s (%d array element%s, %s)", SafeToString( Value ), #Value, #Value == 1 and "" or "s",
			next( Value ) ~= nil and "not empty" or "empty" )
	end
} )

local ToShortKeyByType = table.ShallowMerge( ToShortStringByType, {
	string = function( Value )
		if StringFind( Value, "\n", 1, true ) then
			return StringFormat( "[==[%s]==]", Value )
		end
		return Value
	end
} )

local function ToString( Value, Converters )
	return ( Converters[ type( Value ) ] or SafeToString )( Value )
end

function Inspect.ToString( Value )
	return ToString( Value, ToStringByType )
end

function Inspect.ToShortString( Value )
	return ToString( Value, ToShortStringByType )
end

function Inspect.ToShortStringKey( Key )
	return ToString( Key, ToShortKeyByType )
end

Inspect.SafeToString = SafeToString

return Inspect
