--[[
	Shine's config system.
]]

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message
local pairs = pairs
local StringFormat = string.format
local StringLower = string.lower

local IsType = Shine.IsType

local ConfigPath = "config://shine/BaseConfig"
local BackupPath = "config://Shine_BaseConfig"

local DefaultConfig = {
	EnableLogging = true, -- Enable Shine's internal log. Note that plugins rely on this to log.
	DebugLogging = false,
	LogDir = "config://shine/logs/", -- Logging directory.
	DateFormat = "dd-mm-yyyy", -- Format for logging dates.
	LogLevel = "INFO", -- Log level for core Shine logger.

	ExtensionDir = "config://shine/plugins/", -- Plugin configs directory.

	GetUsersFromWeb = false, -- Sets whether user data should be retrieved from the web.
	GetUsersWithPOST = false, -- Should we use POST to retrieve users?
	UserRetrieveArguments = {}, -- What extra arguments should be sent using POST?
	UsersURL = "http://www.yoursite.com/users.json", -- URL to get user data from if the above is true.
	RefreshUsers = false, -- Auto-refresh users every set amount of time.
	RefreshInterval = 60, -- How long in seconds between refreshes?

	WebConfigs = {
		Enabled = false, -- Should plugins get their configuration files from the web?
		RequestURL = "", -- Where should we request them from?
		RequestArguments = {}, -- What additional POST arguments should we send?
		MaxAttempts = 3, -- How many times should we attempt to get the configs before giving up?
		UpdateMode = 1, -- How should they be updated? 1 = on mapcycle, 2 = timed refresh.
		UpdateInterval = 1, -- How long in minutes between updates if set to time based?
		IsBlacklist = false, -- Is the plugins list a blacklist, or a whitelist?
		Plugins = {} -- List of plugins to get web configs for.
	},

	ActiveExtensions = { -- Defines which plugins should be active.
		adverts = false,
		afkkick = false,
		badges = false,
		ban = true,
		basecommands = true,
		commbans = false,
		funcommands = false,
		logging = false,
		mapvote = true,
		motd = true,
		namefilter = false,
		pingtracker = false,
		pregame = false,
		readyroom = false,
		reservedslots = false,
		roundlimiter = false,
		serverswitch = false,
		tournamentmode = false,
		unstuck = true,
		usermanagement = true,
		votealltalk = false,
		voterandom = false,
		votesurrender = true,
		welcomemessages = false,
		workshopupdater = false
	},

	-- Defines extensions marked as beta that should be loaded.
	-- This allows plugins to be omitted from ActiveExtensions until they're promoted from beta status, at which point
	-- their DefaultState will be respected.
	ActiveBetaExtensions = {},

	APIKeys = {
		Steam = ""
	},

	EqualsCanTarget = false, -- Defines whether users with the same immunity can target each other or not.

	NotifyOnCommand = false, -- Should we display a notification for commands such as kick, ban etc?
	NotifyAnonymous = true, -- Should we hide who performed the operation?
	NotifyAdminAnonymous = false, -- Should we hide to players with greater-equal immunity who performed it?
	ChatName = "Admin", -- The name to use for anonymous output.
	ConsoleName = "Admin", -- The name to use for console running a command.
	MaxCommandsPerSecond = 3, -- The maximum number of (server-side) commands that can be executed in a second by a given client.

	SilentChatCommands = true, -- Defines whether to silence all chat commands, or only those starting with "/".

	AddTag = true, -- Add 'shine' as a server tag.

	ReportErrors = true -- Should errors be reported at the end of a round?
}

local DefaultGamemode = Shine.BaseGamemode

do
	local CheckConfig = Shine.RecursiveCheckConfig

	--[[
		Gets the gamemode dependent config file.
	]]
	local function GetConfigPath( Backup, Default )
		local Gamemode = Shine.GetGamemode()

		if Gamemode == DefaultGamemode or Default then
			return Backup and BackupPath..".json" or ConfigPath..".json"
		end

		return StringFormat( "%s_%s.json", Backup and BackupPath or ConfigPath, Gamemode )
	end

	local function AddTrailingSlashRule( Key )
		return {
			Matches = function( self, Config )
				return not Config[ Key ]:EndsWith( "/" ) and not Config[ Key ]:EndsWith( "\\" )
			end,
			Fix = function( self, Config )
				Notify( StringFormat( "%s missing trailing /, appending...", Key ) )
				Config[ Key ] = Config[ Key ].."/"
			end
		}
	end

	local function InConfigDirectoryRule( Key )
		return {
			Matches = function( self, Config )
				return not Config[ Key ]:StartsWith( "config://" )
			end,
			Fix = function( self, Config )
				Notify( StringFormat( "%s does not point to the config directory, resetting to default...", Key ) )
				Config[ Key ] = DefaultConfig[ Key ]
			end
		}
	end

	local function ValidateExtensionSet( Extensions, FieldName )
		if not IsType( Extensions, "table" ) then return false end

		local Modified = false

		-- For every active extension name, make sure only the lower-case version exists.
		-- If there's one with a different case, remove it.
		local RenamedExtensionValues = {}
		for Name, Enabled in pairs( Extensions ) do
			local LowerCaseName = StringLower( Name )
			if LowerCaseName ~= Name then
				if Extensions[ LowerCaseName ] ~= nil then
					Notify( StringFormat( "Removing duplicate extension '%s' from %s.", Name, FieldName ) )
				else
					Notify( StringFormat(
						"Renaming '%s' to '%s' in %s as extension names must be lower case.",
						Name, LowerCaseName, FieldName
					) )
					-- Modifying during iteration for a key other than the current key will
					-- lead to undefined iteration behaviour.
					RenamedExtensionValues[ LowerCaseName ] = Enabled
				end

				Extensions[ Name ] = nil
				Modified = true
			end
		end

		for Name, Value in pairs( RenamedExtensionValues ) do
			Extensions[ Name ] = Value
		end

		return Modified
	end

	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function( self, Config )
			return Shine.TypeCheckConfig( "base", Config, DefaultConfig, true )
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			return ValidateExtensionSet( Config.ActiveExtensions, "ActiveExtensions" )
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			return ValidateExtensionSet( Config.ActiveBetaExtensions, "ActiveBetaExtensions" )
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			return CheckConfig( Config, DefaultConfig, true )
		end
	} )
	Validator:AddRule( AddTrailingSlashRule( "LogDir" ) )
	Validator:AddRule( InConfigDirectoryRule( "LogDir" ) )
	Validator:AddRule( AddTrailingSlashRule( "ExtensionDir" ) )
	Validator:AddRule( InConfigDirectoryRule( "ExtensionDir" ) )
	Validator:AddFieldRule( "LogLevel", Validator.InEnum(
		Shine.Objects.Logger.LogLevel, Shine.Objects.Logger.LogLevel.INFO
	) )

	function Shine:LoadConfig()
		local Paths = {
			GetConfigPath(),
			GetConfigPath( false, true ),
			GetConfigPath( true ),
			GetConfigPath( true, true )
		}

		local ConfigFile
		local Err
		local Pos

		for i = 1, #Paths do
			local Path = Paths[ i ]

			ConfigFile, Pos, Err = self.LoadJSONFile( Path )

			-- Store what path we've loaded from so we update the right one!
			if ConfigFile ~= false then
				self.ConfigPath = Path

				break
			end
		end

		Notify( "Loading Shine config..." )

		if not ConfigFile or not IsType( ConfigFile, "table" ) then
			if IsType( Pos, "string" ) then
				-- No file exists.
				self:GenerateDefaultConfig( true )
			else
				-- Invalid JSON. Load the default config but don't save.
				self.Config = DefaultConfig
				self.ConfigHasSyntaxError = true

				Notify( StringFormat( "Config has invalid JSON. Error: %s. Loading default...", Err ) )
			end

			return
		end

		self.Config = ConfigFile

		if Validator:Validate( self.Config ) then
			self:SaveConfig()
		end
	end

	function Shine:SaveConfig( Silent )
		if self.ConfigHasSyntaxError then return end

		local ConfigFile, Err = self.SaveJSONFile( self.Config,
			self.ConfigPath or GetConfigPath( false, true ) )

		if not ConfigFile then -- Something's gone horribly wrong!
			Notify( "Error writing config file: "..Err )

			return
		end

		if not Silent then
			Notify( "Updating Shine config..." )
		end
	end
end

function Shine:GenerateDefaultConfig( Save )
	self.Config = DefaultConfig

	if Save then
		self:SaveConfig()
	end
end

local function ConvertToLookup( Table )
	if #Table == 0 then return Table end

	-- I've had the game crash before for not making a new table when doing this...
	local NewTable = {}

	for i = 1, #Table do
		NewTable[ Table[ i ] ] = true
	end

	return NewTable
end

-- Gets all plugins set to load their configs from the web.
local function GetWebLoadingPlugins( self )
	local WebConfig = self.Config.WebConfigs
	if not WebConfig.Enabled then
		return {}
	end

	local ActiveExtensions = self.Config.ActiveExtensions
	local PluginsByName = ConvertToLookup( WebConfig.Plugins )

	if WebConfig.IsBlacklist then
		local LoadFromWeb = {}

		for Plugin, Enabled in pairs( ActiveExtensions ) do
			if not PluginsByName[ Plugin ] and Enabled then
				LoadFromWeb[ Plugin ] = true
			end
		end

		return LoadFromWeb
	end

	return PluginsByName
end

local function LoadPlugin( self, Name )
	if self.Plugins[ Name ] then
		-- We already loaded it, it was a shared plugin.
		local Success, Err = self:EnableExtension( Name )
		Notify( Success and StringFormat( "- Extension '%s' loaded.", Name )
			or StringFormat( "- Error loading %s: %s", Name, Err ) )
	else
		local Success, Err = self:LoadExtension( Name )
		Notify( Success and StringFormat( "- Extension '%s' loaded.", Name )
			or StringFormat( "- Error loading %s: %s", Name, Err ) )
	end
end

function Shine:LoadExtensionConfigs()
	self:LoadConfig()

	self.Logger:SetLevel( self.Config.LogLevel )

	-- Load extensions after the initial configuration load to ensure logging options are available.
	Script.Load "lua/shine/core/shared/extensions.lua"

	if self.Config.AddTag then -- Would be nice to know who's running it.
		Server.AddTag( "shine" )
	end

	local AllPlugins = self.AllPluginsArray
	local ActiveExtensions = self.Config.ActiveExtensions
	local ActiveBetaExtensions = self.Config.ActiveBetaExtensions
	local Modified = false

	local RequestedExtensions = Shine.Set()
	for Plugin, Enabled in pairs( ActiveExtensions ) do
		if Enabled then
			RequestedExtensions:Add( Plugin )
		end
	end
	for Plugin, Enabled in pairs( ActiveBetaExtensions ) do
		if Enabled then
			RequestedExtensions:Add( Plugin )
		end
	end

	local ExtensionsToLoad = {}

	local function GetPluginTable( Plugin )
		local PluginTable = self.Plugins[ Plugin ]

		if not PluginTable then
			self:LoadExtension( Plugin, true )
			PluginTable = self.Plugins[ Plugin ]
		end

		return PluginTable
	end

	-- Find any new plugins we don't have in our config, and add them.
	for i = 1, #AllPlugins do
		local Plugin = AllPlugins[ i ]

		local WasEnabledAsBeta = false
		if ActiveBetaExtensions[ Plugin ] ~= nil then
			WasEnabledAsBeta = ActiveBetaExtensions[ Plugin ]

			-- Clear out any plugins that are no longer in beta.
			local PluginTable = GetPluginTable( Plugin )
			if PluginTable and not PluginTable.IsBeta then
				ActiveBetaExtensions[ Plugin ] = nil
				Modified = true
			end
		end

		if ActiveExtensions[ Plugin ] == nil then
			-- Load, but do not enable, the extension to determine its default state.
			local PluginTable = GetPluginTable( Plugin )

			local DefaultState = false
			if PluginTable and PluginTable.DefaultState ~= nil then
				DefaultState = PluginTable.DefaultState
			end

			if WasEnabledAsBeta then
				DefaultState = true
			end

			if PluginTable.IsBeta then
				if ActiveBetaExtensions[ Plugin ] == nil then
					self:Print(
						"A new beta plugin is available: %s%s. Enable it in ActiveBetaExtensions in the base config, "..
						"using sh_loadplugin or using the admin menu.",
						true,
						Plugin,
						PluginTable.BetaDescription and StringFormat( " - %s", PluginTable.BetaDescription ) or ""
					)

					-- Always start beta extensions in a disabled state.
					ActiveBetaExtensions[ Plugin ] = false
				end
			else
				ActiveExtensions[ Plugin ] = DefaultState
			end

			Modified = true
		end

		local EnabledState = ActiveExtensions[ Plugin ]
		if EnabledState == nil then
			EnabledState = ActiveBetaExtensions[ Plugin ]
		end

		if EnabledState then
			ExtensionsToLoad[ #ExtensionsToLoad + 1 ] = Plugin
		end
	end

	RequestedExtensions:RemoveAll( ExtensionsToLoad )

	if Modified then
		self:SaveConfig( true )
	end

	local DontEnableNow = GetWebLoadingPlugins( self )

	Notify( "Loading extensions..." )

	for i = 1, #ExtensionsToLoad do
		local Plugin = ExtensionsToLoad[ i ]
		if not DontEnableNow[ Plugin ] then
			LoadPlugin( self, Plugin )
		end
	end

	Notify( "Completed loading Shine extensions." )

	if RequestedExtensions:GetCount() > 0 then
		local MissingExtensions = Shine.Stream( RequestedExtensions:AsList() ):Sort():Concat( "\n- " )
		Notify(
			StringFormat(
				"Some extensions could not be loaded as they have not been registered:\n- %s",
				MissingExtensions
			)
		)
	end

	local WebConfig = self.Config.WebConfigs

	if WebConfig.Enabled then
		self.Hook.Add( "OnFirstThink", "LoadWebConfigs", function()
			self:LoadWebPlugins( DontEnableNow )

			if WebConfig.UpdateMode == 2 then
				self.Timer.Create( "WebConfig_Update", WebConfig.UpdateInterval * 60, -1, function()
					self.WebPluginTimeouts = 0
					self:LoadWebPlugins( DontEnableNow, true )
				end )
			end
		end, self.Hook.MAX_PRIORITY )
	end
end

local function LoadDefaultConfigs( self, List )
	-- Just call the default enable, it'll load the disk/default config.
	for i = 1, #List do
		LoadPlugin( self, List[ i ] )
	end
end

local function OnFail( self, List, FailMessage, Format, ... )
	self:Print( FailMessage, Format, ... )

	Notify( "[Shine] Loading cached/default configs..." )

	LoadDefaultConfigs( self, List )

	Notify( "[Shine] Finished loading." )
end

local function ValidateAndSaveConfig( Name, PluginTable )
	if PluginTable:ValidateConfigAfterLoad() then
		Notify( StringFormat( "WARNING: '%s' config required changes to be valid."
			.. " Check the local copy to see what changed.", Name ) )
	end
	PluginTable:SaveConfig( true )
end

local function LoadPluginWithConfig( self, Name, PluginTable, ConfigData, GamemodeName, NeedDifferentPath )
	PluginTable.Config = ConfigData

	-- Set the gamemode config path if we've been given a gamemode config.
	if NeedDifferentPath then
		PluginTable.__ConfigPath = StringFormat( "%s%s/%s",
			self.Config.ExtensionDir, GamemodeName, PluginTable.ConfigName )
	end

	-- Cache to disk.
	ValidateAndSaveConfig( Name, PluginTable )

	if PluginTable.OnWebConfigLoaded then
		PluginTable:OnWebConfigLoaded()
	end

	local Success, Err = self:EnableExtension( Name, true )
	Notify( Success and StringFormat( "- Extension '%s' loaded.", Name )
		or StringFormat( "- Error loading %s: %s", Name, Err ) )
end

local function OnWebPluginSuccess( self, Response, List, Reload )
	if not Response then
		OnFail( self, List, "[WebConfigs] Web request for plugin configs got a blank response. Loading default/cache files..." )

		return
	end

	local Decoded, Pos, Err = Decode( Response )

	if not Decoded or not IsType( Decoded, "table" ) then
		OnFail( self, List, "[WebConfigs] Web request for plugin configs received invalid JSON. Error: %s.\nResponse:\n%s\nLoading default/cache files...",
			true, Err, Response )

		return
	end

	if not Decoded.success and not Decoded.Success then
		OnFail( self, List, "[WebConfigs] Web request for plugin configs received error: %s.",
			true, Decoded.msg or Decoded.Msg or "unknown error" )

		return
	end

	local PluginData = Decoded.plugins or Decoded.Plugins
	if not PluginData then
		OnFail( self, List, "[WebConfigs] Web request for plugin configs received incorrect response. Missing plugins table." )

		return
	end

	if not Reload then
		Notify( "[Shine] Parsing web config response..." )
	end

	local Loaded = {}
	local function ProcessPlugin( Name, Data )
		if not IsType( Name, "string" ) or not IsType( Data, "table" ) then
			self:Print( "[WebConfigs] Server responded with invalid key/value in config table: %s/%s", true, Name, Data )
			if not Reload and IsType( Name, "string" ) then
				Loaded[ Name ] = true
				LoadPlugin( self, Name )
			end
			return
		end

		Loaded[ Name ] = true

		local Success = Data.success or Data.Success
		local ConfigData = Data.config or Data.Config

		-- Is the config we're loading for a specific gamemode?
		local GamemodeName = Data.Gamemode or Data.gamemode
		local NeedDifferentPath = GamemodeName and GamemodeName ~= DefaultGamemode

		if not Success then
			self:Print( "[WebConfigs] Server responded with error for plugin %s: %s.", true,
				Name, Data.msg or Data.Msg or "unknown error" )

			if not Reload then
				LoadPlugin( self, Name )
			end
		elseif ConfigData then
			local PluginTable = self.Plugins[ Name ]

			if PluginTable then
				if Reload then
					-- Reloading means we just need to update the given config keys.
					for Key, Value in pairs( ConfigData ) do
						PluginTable.Config[ Key ] = Value
					end

					ValidateAndSaveConfig( Name, PluginTable )

					if PluginTable.OnWebConfigReloaded then
						PluginTable:OnWebConfigReloaded()
					end
				else
					LoadPluginWithConfig( self, Name, PluginTable, ConfigData, GamemodeName, NeedDifferentPath )
				end
			-- We don't want to enable new extensions on reload.
			elseif not Reload then
				local Success, Err = self:LoadExtension( Name, true )

				if not Success then
					Notify( StringFormat( "- Error loading %s: %s", Name, Err ) )
				else
					PluginTable = self.Plugins[ Name ]
					LoadPluginWithConfig( self, Name, PluginTable, ConfigData, GamemodeName, NeedDifferentPath )
				end
			end
		else
			self:Print( "[WebConfigs] Server responded with success but supplied no config for plugin %s.", true, Name )

			if not Reload then
				LoadPlugin( self, Name )
			end
		end
	end

	for Name, Data in SortedPairs( PluginData ) do
		ProcessPlugin( Name, Data )
	end

	if not Reload then
		-- Make sure any entries that weren't provided in the response are still loaded.
		for i = 1, #List do
			local Name = List[ i ]
			if not Loaded[ Name ] then
				self:Print( "[WebConfigs] No data was provided for plugin %s, so it was loaded from disk.", true, Name )
				LoadPlugin( self, Name )
			end
		end
	end

	if not Reload then
		Notify( "[Shine] Finished parsing web config response." )
	end
end

local function OnWebPluginFailure( self, Plugins, Reload )
	if Reload then return end

	Notify( "[Shine] Web config retrieval reached max retries. Loading extensions from cache/default configs..." )

	for i = 1, #Plugins do
		LoadPlugin( self, Plugins[ i ] )
	end

	Notify( "[Shine] Finished loading." )
end

--[[
	Loads plugins set to get their configs from the web.

	Sets up a timed HTTP request for the configs.

	Inputs: Plugins in lookup table form (from the original startup), boolean to signal reloading so we
	don't overwrite configs or reload extensions if we have a problem.
]]
function Shine:LoadWebPlugins( Plugins, Reload )
	local List = {}
	local Count = 0

	for Plugin in SortedPairs( Plugins ) do
		Count = Count + 1
		List[ Count ] = Plugin
	end

	if Count == 0 then return end

	local WebConfig = self.Config.WebConfigs

	local Args = {
		plugins = Encode( List ),
		gamemode = self.GetGamemode()
	}

	for Arg, Value in pairs( WebConfig.RequestArguments ) do
		Args[ Arg ] = Value
	end

	self.HTTPRequestWithRetry( WebConfig.RequestURL, "POST", Args, {
		OnSuccess = function( Response )
			OnWebPluginSuccess( self, Response, List, Reload )
		end,
		OnFailure = function()
			OnWebPluginFailure( self, List, Reload )
		end,
		OnTimeout = function( Attempt )
			self:Print( "[WebConfigs] Timeout number %i on web plugin config retrieval.", true, Attempt )
		end
	}, WebConfig.MaxAttempts )
end

Shine:LoadExtensionConfigs()

Shine.Hook.CallOnce( "PostloadConfig" )
