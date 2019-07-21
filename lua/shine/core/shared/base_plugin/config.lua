--[[
	Configuration module.
]]

local Shine = Shine

local IsType = Shine.IsType
local Notify = Shared.Message
local select = select
local rawget = rawget
local StringFormat = string.format

local function Print( ... )
	return Notify( StringFormat( ... ) )
end
local function PrintToLog( Message, ... )
	if Server then
		Shine:Print( Message, select( "#", ... ) > 0, ... )
	else
		Print( Message, ... )
	end
end

local ConfigModule = {}

local ClientConfigPath = "config://shine/cl_plugins/"

function ConfigModule:GenerateDefaultConfig( Save )
	self.Config = self.DefaultConfig
	self.Config.__Version = self.Version or "1.0"

	if Save then
		local Path = Server and Shine.Config.ExtensionDir..self.ConfigName
			or ClientConfigPath..self.ConfigName

		local Success, Err = Shine.SaveJSONFile( self.Config, Path )

		if not Success then
			PrintToLog( "[Error] Error writing %s config file: %s", self.__Name, Err )

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
		PrintToLog( "[Error] Error writing %s config file: %s", self.__Name, Err )
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

		-- Look for gamemode specific config file.
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
			PrintToLog( "[Error] Invalid JSON for %s plugin config. Error: %s. Loading default...", self.__Name, Err )

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

	-- Do not permit loading a newer config version than the plugin.
	Shine.AssertAtLevel( CurrentConfigVersion < OurVersion,
		"Configuration on disk (%s) is a newer version than the loaded plugin (%s).", 0,
		CurrentConfigVersion, OurVersion )

	PrintToLog(
		"Updating %s config from version %s to %s...",
		self.__Name, CurrentConfigVersion, self.Version or "1.0"
	)

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

if Client then
	local TableShallowMerge = table.ShallowMerge

	local ParameterTypes = {
		Boolean = function( self, ConfigKey, Command, Options )
			Command:AddParam{
				Type = "boolean",
				Optional = true,
				Default = function() return not self.Config[ ConfigKey ] end
			}
		end,
		Radio = function( self, ConfigKey, Command, Options )
			Command:AddParam{
				Type = "enum",
				Values = Options.Options,
				Optional = true,
				Default = self.DefaultConfig[ ConfigKey ]
			}
		end,
		Slider = function( self, ConfigKey, Command, Options )
			Command:AddParam{
				Type = "number",
				Min = Options.Min,
				Max = Options.Max,
				Optional = true,
				Default = Options.IsPercentage and function()
					return self.DefaultConfig[ ConfigKey ] * 100
				end or self.DefaultConfig[ ConfigKey ]
			}
		end,
		Dropdown = function( self, ConfigKey, Command, Options )
			Command:AddParam{
				Type = "enum",
				Values = Options.Options,
				Optional = true,
				Default = self.DefaultConfig[ ConfigKey ]
			}
		end
	}

	function ConfigModule:AddClientSetting( ConfigKey, Command, Options )
		local Group = self.ConfigGroup
		local ConfigOption = Options.ConfigOption or function() return self.Config[ ConfigKey ] end
		if Options.IsPercentage then
			ConfigOption = function()
				return self.Config[ ConfigKey ] * 100
			end
		end

		local MergedOptions = TableShallowMerge( Options, {
			Command = Command,
			ConfigOption = ConfigOption,
			TranslationSource = self:GetName(),
			Group = Group and {
				Key = Group.Key or "CLIENT_CONFIG_TAB",
				Source = self:GetName(),
				Icon = Group.Icon
			}
		} )

		Shine:RegisterClientSetting( MergedOptions )

		if not self:HasRegisteredCommand( Command ) then
			local CommandMessage = Options.CommandMessage
			if CommandMessage and not IsType( CommandMessage, "function" ) then
				local Message = CommandMessage
				CommandMessage = function( Value )
					return StringFormat( Message, Value )
				end
			end

			local Transformer = Options.ValueTransformer
			if Options.IsPercentage then
				Transformer = function( Value ) return Value * 0.01 end
			end

			local OnChange = Options.OnChange

			local Command = self:BindCommand( Command, function( Value )
				if CommandMessage then
					Notify( CommandMessage( Value ) )
				else
					Print( "%s set to: %s", ConfigKey, MaxVisibleMessages )
				end

				if Transformer then
					Value = Transformer( Value )
				end

				self.Config[ ConfigKey ] = Value
				self:SaveConfig()

				if OnChange then
					OnChange( self, Value )
				end
			end )

			local ArgumentAdder = ParameterTypes[ Options.Type ]
			if ArgumentAdder then
				ArgumentAdder( self, ConfigKey, Command, Options )
			else
				Command:AddParam{
					Type = "string", Default = self.DefaultConfig[ ConfigKey ], TakeRestOfLine = true
				}
			end
		end
	end

	function ConfigModule:AddClientSettings( Settings )
		for i = 1, #Settings do
			local Setting = Settings[ i ]
			self:AddClientSetting( Setting.ConfigKey, Setting.Command, Setting )
		end
	end
end

Shine.BasePlugin:AddModule( ConfigModule )
