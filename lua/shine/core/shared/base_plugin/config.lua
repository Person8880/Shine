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

	if self:ValidateConfigAfterLoad() then
		self:SaveConfig()
	end
end

--[[
	Validates the plugin's configuration, returning true if changes
	were made.
]]
function ConfigModule:ValidateConfigAfterLoad()
	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function( _, Config )
			return self.PreValidateConfig and self:PreValidateConfig( Config )
		end
	} )
	Validator:AddRule( {
		Matches = function( _, Config )
			return self:MigrateConfig( Config )
		end
	} )
	Validator:AddRule( {
		Matches = function( _, Config )
			if self.CheckConfig then
				local ReservedKeys = { __Version = true }

				if self.CheckConfigRecursively then
					return Shine.VerifyConfig( Config, self.DefaultConfig, ReservedKeys )
				end

				return Shine.CheckConfig( Config, self.DefaultConfig, false, ReservedKeys )
			end
		end
	} )
	Validator:AddRule( {
		Matches = function( _, Config )
			return self.CheckConfigTypes and self:TypeCheckConfig( Config )
		end
	} )
	if self.ConfigValidator then
		Validator:Add( self.ConfigValidator )
	end

	return Validator:Validate( self.Config )
end

function ConfigModule:MigrateConfig( Config )
	local CurrentConfigVersion = Shine.VersionHolder( Config.__Version or "0" )
	local OurVersion = Shine.VersionHolder( self.Version or "1.0" )
	if CurrentConfigVersion == OurVersion then return end

	Print( "Updating %s config from version %s to %s...", self.__Name, CurrentConfigVersion, self.Version or "1.0" )

	Config.__Version = self.Version or "1.0"

	local MigrationSteps = self.ConfigMigrationSteps
	if not MigrationSteps then return true end

	local StartingStep
	local EndStep = #MigrationSteps

	-- Find the first step that migrates to a version later than the config's current version.
	for i = 1, EndStep do
		local Step = MigrationSteps[ i ]
		if Shine.VersionHolder( Step.VersionTo ) > CurrentConfigVersion then
			StartingStep = i
			break
		end
	end

	if not StartingStep then return true end

	for i = StartingStep, EndStep do
		MigrationSteps[ i ].Apply( Config )
	end

	return true
end

function ConfigModule:TypeCheckConfig( Config )
	return Shine.TypeCheckConfig( self.__Name, Config, self.DefaultConfig )
end

Shine.BasePlugin:AddModule( ConfigModule )
