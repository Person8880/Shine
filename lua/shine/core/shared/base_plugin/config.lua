--[[
	Configuration module.
]]

local Shine = Shine

local IsType = Shine.IsType
local Notify = Shared.Message
local rawget = rawget
local StringFormat = string.format

local function Print( ... )
	return Notify( StringFormat( ... ) )
end

local ConfigModule = {}

local ClientConfigPath = "config://shine/cl_plugins/"

function ConfigModule:GenerateDefaultConfig( Save )
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

function ConfigModule:SaveConfig( Silent )
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

function ConfigModule:LoadConfig()
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
			return self.PreValidateConfig and self:PreValidateConfig( Config )
		end
	} )
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

function ConfigModule:TypeCheckConfig()
	return Shine.TypeCheckConfig( self.__Name, self.Config, self.DefaultConfig )
end

Shine.BasePlugin:AddModule( ConfigModule )
