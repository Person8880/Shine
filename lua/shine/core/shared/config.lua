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

	return Decode( Data )
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
function Shine.CheckConfig( Config, DefaultConfig, DontRemove )
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
	ShowWebInSteamBrowser = false,
	ReportErrors = true,
	AnimateUI = true
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

	self.Config = Data

	if self.CheckConfig( self.Config, DefaultConfig ) then
		self:SaveClientBaseConfig()
	end
end

function Shine:SaveClientBaseConfig()
	local Success, Err = self.SaveJSONFile( self.Config, BaseConfig )
end

Shine:LoadClientBaseConfig()

local function MakeClientOption( Command, OptionKey, OptionString, Yes, No )
	local ConCommand = Shine:RegisterClientCommand( Command, function( Bool )
		Shine.Config[ OptionKey ] = Bool

		Notify( StringFormat( "[Shine] %s %s.", OptionString, Bool and Yes or No ) )

		Shine:SaveClientBaseConfig()
	end )
	ConCommand:AddParam{ Type = "boolean", Optional = true,
		Default = function() return not Shine.Config[ OptionKey ] end }
end

local Options = {
	{
		Data = {
			"sh_disableweb", "DisableWebWindows",
			"Web page display has been", "disabled", "enabled"
		},
		MessageState = false,
		Message = "Shine is set to display web pages from plugins. If you wish to globally disable web page display, then enter \"sh_disableweb 1\" into the console."
	},
	{
		Data = {
			"sh_viewwebinsteam", "ShowWebInSteamBrowser",
			"Web page display set to", "Steam browser", "in game window"
		},
		MessageState = true,
		Message = "Shine is set to display web pages in the Steam overlay. If you wish to show them using the in game browser, then enter \"sh_viewwebinsteam 0\" into the console."
	},
	{
		Data = {
			"sh_errorreport", "ReportErrors",
			"Error reporting has been", "enabled", "disabled"
		},
		MessageState = true,
		Message = "Shine is set to report any errors it causes on your client when you disconnect. If you do not wish it to do so, then enter \"sh_errorreport 0\" into the console."
	},
	{
		Data = {
			"sh_animateui", "AnimateUI",
			"UI animations have been", "enabled", "disabled"
		},
		AlwaysShowMessage = true,
		Message = "You can enable/disable UI animations by entering \"sh_animateui\" into the console."
	}
}

for i = 1, #Options do
	local Option = Options[ i ]

	MakeClientOption( unpack( Option.Data ) )
	if Shine.Config[ Option.Data[ 2 ] ] == Option.MessageState or Option.AlwaysShowMessage then
		Shine.AddStartupMessage( Option.Message )
	end
end
