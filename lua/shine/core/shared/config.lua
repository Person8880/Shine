--[[
	Shared config stuff.
]]

local Encode, Decode = json.encode, json.decode
local Open = io.open

local JSONSettings = { indent = true, level = 1 }

local IsType = Shine.IsType

function Shine.LoadJSONFile( Path )
	local File, Err = Open( Path, "r" )

	if not File then
		return nil, Err
	end

	local Data = File:read( "*all" )

	File:close()

	local Ret = Decode( Data )

	return Ret
end

function Shine.SaveJSONFile( Table, Path )
	local File, Err = Open( Path, "w+" )

	if not File then
		return nil, Err
	end

	File:write( Encode( Table, JSONSettings ) )

	File:close()

	return true
end

--Checks a config for missing entries including sub-tables.
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
function Shine.CheckConfig( Config, DefaultConfig )
	local Updated

	--Add new keys.
	for Option, Value in pairs( DefaultConfig ) do
		if Config[ Option ] == nil then
			Config[ Option ] = Value

			Updated = true
		end
	end

	--Remove old keys.
	for Option, Value in pairs( Config ) do
		if DefaultConfig[ Option ] == nil then
			Config[ Option ] = nil

			Updated = true
		end
	end

	return Updated
end

if Server then return end

local Notify = Shared.Message
local StringFormat = string.format

local BaseConfig = "config://shine/cl_config.json"

local DefaultConfig = {
	DisableWebWindows = false,
	ShowWebInSteamBrowser = false
}

function Shine:CreateClientBaseConfig()
	local Success, Err = self.SaveJSONFile( DefaultConfig, BaseConfig )

	self.Config = DefaultConfig
end

function Shine:LoadClientBaseConfig()
	local Data, Err = self.LoadJSONFile( BaseConfig )

	if not Data then
		self:CreateClientBaseConfig()

		return
	end

	self.Config = Data or {}

	if self.CheckConfig( self.Config, DefaultConfig ) then
		self:SaveClientBaseConfig()
	end
end

function Shine:SaveClientBaseConfig()
	local Success, Err = self.SaveJSONFile( self.Config, BaseConfig )
end

Shine:LoadClientBaseConfig()

local DisableWeb = Shine:RegisterClientCommand( "sh_disableweb", function( Bool )
	Shine.Config.DisableWebWindows = Bool

	Notify( StringFormat( "[Shine] Web page display has been %s.", Bool and "disabled" or "enabled" ) )

	Shine:SaveClientBaseConfig()
end )
DisableWeb:AddParam{ Type = "boolean", Optional = true, Default = function() return not Shine.Config.DisableWebWindows end }

local SteamWeb = Shine:RegisterClientCommand( "sh_viewwebinsteam", function( Bool )
	Shine.Config.ShowWebInSteamBrowser = Bool

	Notify( StringFormat( "[Shine] Web page display set to %s.", Bool and "Steam browser" or "in game window" ) )

	Shine:SaveClientBaseConfig()
end )
SteamWeb:AddParam{ Type = "boolean", Optional = true, Default = function() return not Shine.Config.ShowWebInSteamBrowser end }
