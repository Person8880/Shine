--[[
	Configuration module.
]]

local Shine = Shine

local IsType = Shine.IsType
local Notify = Shared.Message
local select = select
local rawget = rawget
local StringFormat = string.format
local tostring = tostring

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
local GetConfigurationPath

if Server then
	GetConfigurationPath = function( self )
		return Shine.Config.ExtensionDir..self.ConfigName
	end
else
	-- Note: both client and predict VMs share the same configuration folder, as predicted plugins ought to be using
	-- the same client-side configuration in both VMs.
	GetConfigurationPath = function( self )
		return ClientConfigPath..self.ConfigName
	end
end

function ConfigModule:GenerateDefaultConfig( Save )
	self.Config = self.DefaultConfig
	self.Config.__Version = self.Version or "1.0"

	if Save and not Predict then
		local Path = GetConfigurationPath( self )
		local Success, Err = Shine.SaveJSONFile( self.Config, Path )

		if not Success then
			PrintToLog( "[Error] Error writing %s config file: %s", self.__Name, Err )

			return
		end

		Print( "Shine %s config file created.", self.__Name )
	end
end

function ConfigModule:SaveConfig( Silent )
	if Predict then
		Print( "[Warn] Ignoring request to save configuration for %s in prediction VM!", self.__Name )
		return
	end

	local Path
	if Server then
		Path = rawget( self, "__ConfigPath" ) or GetConfigurationPath( self )
	else
		Path = GetConfigurationPath( self )
	end

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
	local Path = GetConfigurationPath( self )

	local ErrorMessage
	local ErrorPosition

	if Server then
		local Gamemode = Shine.GetGamemode()

		-- Look for gamemode specific config file.
		if Gamemode ~= Shine.BaseGamemode then
			local Paths = {
				StringFormat( "%s%s/%s", Shine.Config.ExtensionDir, Gamemode, self.ConfigName ),
				Path
			}

			for i = 1, #Paths do
				local FilePath = Paths[ i ]
				if Shine.FileExists( FilePath ) then
					local File, ErrPos, ErrString = Shine.LoadJSONFile( FilePath )
					if File then
						PluginConfig = File

						self.__ConfigPath = FilePath

						break
					end

					if IsType( ErrPos, "number" ) then
						-- JSON syntax error.
						ErrorMessage = ErrString
						ErrorPosition = ErrPos
					else
						-- File reading error.
						ErrorMessage = ErrPos
						ErrorPosition = nil
					end
				end
			end
		elseif Shine.FileExists( Path ) then
			PluginConfig, ErrorPosition, ErrorMessage = Shine.LoadJSONFile( Path )
		end
	elseif Shine.FileExists( Path ) then
		PluginConfig, ErrorPosition, ErrorMessage = Shine.LoadJSONFile( Path )
	end

	if not PluginConfig or not IsType( PluginConfig, "table" ) then
		if not PluginConfig and not ErrorPosition and not ErrorMessage then
			-- No file found, generate the default config and save it.
			self:GenerateDefaultConfig( true )
			self.__IsNewConfig = true
		else
			if PluginConfig ~= nil and not IsType( PluginConfig, "table" ) then
				-- Was valid JSON, but not an object. Treat it as invalid JSON.
				ErrorPosition = 0
				ErrorMessage = StringFormat(
					"expected JSON object, got %s (check the file starts with '{' and ends with '}')",
					type( PluginConfig )
				)
			else
				-- Was not valid JSON.
				ErrorMessage = ErrorMessage or ( IsType( ErrorPosition, "string" ) and ErrorPosition )
					or "unknown error reading file"
			end

			-- Either the file exists but has invalid JSON (and so there's an error position), or the file couldn't be
			-- read.
			local ErrorKey
			if IsType( ErrorPosition, "number" ) then
				ErrorKey = "ERROR_INVALID_JSON_IN_PLUGIN_CONFIG"
				PrintToLog(
					"[Error] Invalid JSON for %s plugin config. Error: %s. Loading default...",
					self.__Name,
					ErrorMessage
				)
			else
				ErrorKey = "ERROR_FAILED_TO_READ_PLUGIN_CONFIG"
				PrintToLog(
					"[Error] Failed to read %s plugin config file. Error: %s. Loading default...",
					self.__Name,
					ErrorMessage
				)
			end

			self.Config = self.DefaultConfig

			if Server then
				Shine.SystemNotifications:AddNotification( {
					Type = Shine.SystemNotifications.Type.ERROR,
					Message = {
						Source = "Core",
						TranslationKey = ErrorKey,
						Context = ErrorMessage
					},
					Source = {
						Type = Shine.SystemNotifications.Source.PLUGIN,
						ID = self.__Name
					}
				} )
			end
		end

		return
	end

	self.Config = PluginConfig

	if self:ValidateConfigAfterLoad() and not Predict then
		self:SaveConfig()
	end
end

local AutoRegisterValidators
if Client then
	local ValidatorRules = {
		Colour = function( self, ConfigKey, Options, Validator )
			Validator:AddFieldRule( ConfigKey, Validator.IsType( "table", {} ) )
			Validator:AddFieldRule( ConfigKey, Validator.HasLength( 3, 255 ) )
			Validator:AddFieldRule( ConfigKey, Validator.AllValuesSatisfy(
				Validator.IsType( "number", 255 ),
				Validator.Clamp( 0, 255 )
			) )
		end,
		Radio = function( self, ConfigKey, Options, Validator )
			Validator:AddFieldRule( ConfigKey, Validator.InEnum( Options.Options, self.DefaultConfig[ ConfigKey ] ) )
		end,
		Slider = function( self, ConfigKey, Options, Validator )
			local Min, Max = Options.Min, Options.Max
			if Options.IsPercentage then
				Min = Min * 0.01
				Max = Max * 0.01
			end
			Validator:AddFieldRule( ConfigKey, Validator.Clamp( Min, Max ) )
		end,
		Dropdown = function( self, ConfigKey, Options, Validator )
			Validator:AddFieldRule( ConfigKey, Validator.InEnum( Options.Options, self.DefaultConfig[ ConfigKey ] ) )
		end
	}

	local function AddValidationRule( self, ConfigKey, Options )
		local Rule = ValidatorRules[ Options.Type ]
		if Rule and ( not self.ConfigValidator or not self.ConfigValidator:HasFieldRule( ConfigKey ) ) then
			self.ConfigValidator = self.ConfigValidator or Shine.Validator()
			Rule( self, ConfigKey, Options, self.ConfigValidator )
		end
	end

	AutoRegisterValidators = function( self )
		if not self.ClientConfigSettings then return end

		for i = 1, #self.ClientConfigSettings do
			local Setting = self.ClientConfigSettings[ i ]
			AddValidationRule( self, Setting.ConfigKey, Setting )
		end
	end
else
	AutoRegisterValidators = function() end
end

--[[
	Indicates whether the plugin has loaded from a newly generated configuration (i.e. the first time the plugin has
	ever been loaded) or not.
]]
function ConfigModule:HasLoadedNewConfig()
	return not not rawget( self, "__IsNewConfig" )
end

--[[
	Validates the plugin's configuration, returning true if changes
	were made.
]]
function ConfigModule:ValidateConfigAfterLoad()
	local MessagePrefix
	if Client then
		MessagePrefix = StringFormat( "[Shine] %s config validation error: ", self:GetName() )
	end

	local Validator = Shine.Validator( MessagePrefix )
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

	AutoRegisterValidators( self )

	if self.ConfigValidator then
		if MessagePrefix and self.ConfigValidator.MessagePrefix == "" then
			self.ConfigValidator.MessagePrefix = MessagePrefix
		end
		Validator:Add( self.ConfigValidator )
	end

	local Changed = self.PreValidateConfig and self:PreValidateConfig( self.Config )
	local Migrated = self:MigrateConfig( self.Config )
	local ValidationFixedErrors = Validator:Validate( self.Config ) or Changed

	if ValidationFixedErrors and Server then
		Shine.SystemNotifications:AddNotification( {
			Type = Shine.SystemNotifications.Type.WARNING,
			Message = {
				Source = "Core",
				TranslationKey = "WARNING_PLUGIN_CONFIG_VALIDATION_ERRORS",
				Context = ""
			},
			Source = {
				Type = Shine.SystemNotifications.Source.PLUGIN,
				ID = self:GetName()
			}
		} )
	end

	return not not ( Migrated or ValidationFixedErrors )
end

function ConfigModule:MigrateConfig( Config )
	local PluginVersion = self.Version or "1.0"
	local CurrentConfigVersion = Shine.VersionHolder( Config.__Version or "0" )
	local OurVersion = Shine.VersionHolder( PluginVersion )
	if CurrentConfigVersion == OurVersion then return end

	-- Do not permit loading a newer config version than the plugin.
	Shine.AssertAtLevel( CurrentConfigVersion < OurVersion,
		"Configuration on disk (%s) is a newer version than the loaded plugin (%s).", 0,
		CurrentConfigVersion, OurVersion )

	PrintToLog(
		"Updating %s config from version %s to %s...",
		self.__Name, CurrentConfigVersion, self.Version or "1.0"
	)

	if Server then
		Shine.SystemNotifications:AddNotification( {
			Type = Shine.SystemNotifications.Type.INFO,
			Message = {
				Source = "Core",
				TranslationKey = "INFO_PLUGIN_VERSION_UPDATE",
				Context = tostring( OurVersion )
			},
			Source = {
				Type = Shine.SystemNotifications.Source.PLUGIN,
				ID = self.__Name
			}
		} )
	end

	Shine.ApplyConfigMigration( Config, {
		NewVersion = PluginVersion,
		CurrentVersion = CurrentConfigVersion,
		MigrationSteps = self.ConfigMigrationSteps
	} )

	return true
end

function ConfigModule:TypeCheckConfig( Config )
	return Shine.TypeCheckConfig( self.__Name, Config, self.DefaultConfig )
end

if Client then
	local CaseFormatType = string.CaseFormatType
	local StringTransformCase = string.TransformCase
	local TableShallowMerge = table.ShallowMerge

	function ConfigModule:Initialise()
		if IsType( self.ClientConfigSettings, "table" ) then
			self:AddClientSettings( self.ClientConfigSettings )
		end
	end

	local ParameterTypes = {
		Boolean = function( self, ConfigKey, Command, Options )
			Command:AddParam{
				Type = "boolean",
				Optional = true,
				Default = function() return not self.Config[ ConfigKey ] end
			}
		end,
		Colour = function( self, ConfigKey, Command, Options )
			Command:AddParam{
				Type = "colour",
				TakeRestOfLine = true,
				Optional = true,
				Default = self.DefaultConfig[ ConfigKey ]
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

	local PostProcessors = {
		Dropdown = function( self, SettingOptions )
			local Options = SettingOptions.Options
			local OptionsTooltips = SettingOptions.OptionTooltips

			SettingOptions.Options = function()
				local DropdownOptions = {}
				local KeyPrefix = StringTransformCase(
					SettingOptions.ConfigKey, CaseFormatType.UPPER_CAMEL, CaseFormatType.UPPER_UNDERSCORE
				)

				for i = 1, #Options do
					local Value = Options[ i ]

					local Tooltip
					if OptionsTooltips and OptionsTooltips[ Value ] then
						Tooltip = self:GetPhrase( OptionsTooltips[ Value ] )
					end

					DropdownOptions[ #DropdownOptions + 1 ] = {
						Text = self:GetPhrase( StringFormat( "%s_%s", KeyPrefix, Value ) ),
						Value = Value,
						Tooltip = Tooltip
					}
				end

				return DropdownOptions
			end

			return SettingOptions
		end
	}

	local function DeriveKey( ConfigKey, Suffix )
		return StringTransformCase(
			ConfigKey, CaseFormatType.UPPER_CAMEL, CaseFormatType.UPPER_UNDERSCORE
		)..Suffix
	end

	local function RegisterCommandIfNecessary( self, ConfigKey, Command, Options )
		if self:HasRegisteredCommand( Command ) then return end

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
			local OriginalValue = Value
			if Transformer then
				Value = Transformer( Value )
			end

			if self:SetClientSetting( ConfigKey, Value ) then
				if CommandMessage then
					Notify( CommandMessage( OriginalValue ) )
				else
					Print( "%s set to: %s", ConfigKey, MaxVisibleMessages )
				end

				if OnChange then
					OnChange( self, Value )
				end
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

	function ConfigModule:AddClientSetting( ConfigKey, Command, Options )
		local Group = self.ConfigGroup
		local ConfigOption = Options.ConfigOption or function() return self.Config[ ConfigKey ] end
		if Options.IsPercentage then
			ConfigOption = function()
				return self.Config[ ConfigKey ] * 100
			end
		end

		local Tooltip
		if Options.Tooltip == true then
			Tooltip = DeriveKey( ConfigKey, "_TOOLTIP" )
		elseif IsType( Options.Tooltip, "string" ) then
			Tooltip = Options.Tooltip
		end

		local OptionTooltips
		if Options.OptionTooltips == true then
			OptionTooltips = {}
			for i = 1, #Options.Options do
				local Value = Options.Options[ i ]
				OptionTooltips[ Value ] = DeriveKey( ConfigKey, StringFormat( "_%s_TOOLTIP", Value ) )
			end
		elseif IsType( Options.OptionTooltips, "table" ) then
			OptionTooltips = Options.OptionTooltips
		end

		local MergedOptions = TableShallowMerge( Options, {
			ConfigKey = ConfigKey,
			Command = Command,
			ConfigOption = ConfigOption,
			Description = Options.Description or DeriveKey( ConfigKey, "_DESCRIPTION" ),
			TranslationSource = self:GetName(),
			Group = Group and {
				Key = Group.Key or "CLIENT_CONFIG_TAB",
				Source = self:GetName(),
				Icon = Group.Icon
			},
			Tooltip = Tooltip,
			OptionTooltips = OptionTooltips,
			DefaultValue = self.DefaultConfig[ ConfigKey ]
		} )

		local PostProcessor = PostProcessors[ Options.Type ]
		if PostProcessor then
			MergedOptions = PostProcessor( self, MergedOptions )
		end

		Shine:RegisterClientSetting( MergedOptions )

		RegisterCommandIfNecessary( self, ConfigKey, Command, Options )

		self.RegisteredClientSettings = rawget( self, "RegisteredClientSettings" ) or {}
		self.RegisteredClientSettings[ MergedOptions.ConfigKey ] = MergedOptions
	end

	function ConfigModule:AddClientSettings( Settings )
		for i = 1, #Settings do
			local Setting = Settings[ i ]
			self:AddClientSetting( Setting.ConfigKey, Setting.Command, Setting )
		end
	end

	function ConfigModule:SetClientSetting( ConfigKey, Value )
		if Value == self.Config[ ConfigKey ] then return false end

		self.Config[ ConfigKey ] = Value
		self:SaveConfig( true )

		local Setting = self.RegisteredClientSettings[ ConfigKey ]
		if Setting then
			if Setting.IsPercentage then
				Value = Value * 100
			end
			Shine.Hook.Broadcast( "OnPluginClientSettingChanged", self, Setting, Value )
		end

		return true
	end

	function ConfigModule:Cleanup()
		local RegisteredClientSettings = rawget( self, "RegisteredClientSettings" )
		if not RegisteredClientSettings then return end

		for ConfigKey, Option in pairs( RegisteredClientSettings ) do
			Shine:RemoveClientSetting( Option )
		end
	end
end

Shine.BasePlugin:AddModule( ConfigModule )
