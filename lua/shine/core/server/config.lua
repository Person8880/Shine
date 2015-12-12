--[[
	Shine's config system.
]]

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message
local pairs = pairs
local StringFormat = string.format

local IsType = Shine.IsType

local ConfigPath = "config://shine/BaseConfig"
local BackupPath = "config://Shine_BaseConfig"

local DefaultConfig = {
	EnableLogging = true, --Enable Shine's internal log. Note that plugins rely on this to log.
	DebugLogging = false,
	LogDir = "config://shine/logs/", --Logging directory.
	DateFormat = "dd-mm-yyyy", --Format for logging dates.

	ExtensionDir = "config://shine/plugins/", --Plugin configs directory.

	GetUsersFromWeb = false, --Sets whether user data should be retrieved from the web.
	GetUsersWithPOST = false, --Should we use POST to retrieve users?
	UserRetrieveArguments = {}, --What extra arguments should be sent using POST?
	UsersURL = "http://www.yoursite.com/users.json", --URL to get user data from if the above is true.
	RefreshUsers = false, --Auto-refresh users every set amount of time.
	RefreshInterval = 60, --How long in seconds between refreshes?

	WebConfigs = {
		Enabled = false, --Should plugins get their configuration files from the web?
		RequestURL = "", --Where should we request them from?
		RequestArguments = {}, --What additional POST arguments should we send?
		MaxAttempts = 3, --How many times should we attempt to get the configs before giving up?
		UpdateMode = 1, --How should they be updated? 1 = on mapcycle, 2 = timed refresh.
		UpdateInterval = 1, --How long in minutes between updates if set to time based?
		IsBlacklist = false, --Is the plugins list a blacklist, or a whitelist?
		Plugins = {} --List of plugins to get web configs for.
	},

	ActiveExtensions = { --Defines which plugins should be active.
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
		voterandom = false,
		votesurrender = true,
		welcomemessages = false,
		workshopupdater = false
	},

	EqualsCanTarget = false, --Defines whether users with the same immunity can target each other or not.

	NotifyOnCommand = false, --Should we display a notification for commands such as kick, ban etc?
	NotifyAnonymous = true, --Should we hide who performed the operation?
	NotifyAdminAnonymous = false, --Should we hide to players with greater-equal immunity who performed it?
	ChatName = "Admin", --The name to use for anonymous output.
	ConsoleName = "Admin", --The name to use for console running a command.

	SilentChatCommands = true, --Defines whether to silence all chat commands, or only those starting with "/".

	AddTag = true, --Add 'shine' as a server tag.

	ReportErrors = true --Should errors be reported at the end of a round?
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

	local Validator = Shine.Validator()
	Validator:AddRule( {
		Matches = function( self, Config )
			return Shine.TypeCheckConfig( "base", Config, DefaultConfig, true )
		end
	} )
	Validator:AddRule( {
		Matches = function( self, Config )
			return CheckConfig( Config, DefaultConfig, true )
		end
	} )
	Validator:AddRule( AddTrailingSlashRule( "LogDir" ) )
	Validator:AddRule( AddTrailingSlashRule( "ExtensionDir" ) )

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

			--Store what path we've loaded from so we update the right one!
			if ConfigFile then
				self.ConfigPath = Path

				break
			end
		end

		Notify( "Loading Shine config..." )

		if not ConfigFile or not IsType( ConfigFile, "table" ) then
			if IsType( Pos, "string" ) then
				--No file exists.
				self:GenerateDefaultConfig( true )
			else
				--Invalid JSON. Load the default config but don't save.
				self.Config = DefaultConfig

				Notify( "Config has invalid JSON, loading default..." )
			end

			return
		end

		self.Config = ConfigFile

		if Validator:Validate( self.Config ) then
			self:SaveConfig()
		end
	end

	function Shine:SaveConfig( Silent )
		local ConfigFile, Err = self.SaveJSONFile( self.Config,
			self.ConfigPath or GetConfigPath( false, true ) )

		if not ConfigFile then --Something's gone horribly wrong!
			Shine.Error = "Error writing config file: "..Err

			Notify( Shine.Error )

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
	local Count = #Table

	if Count == 0 then return Table end

	--I've had the game crash before for not making a new table when doing this...
	local NewTable = {}

	for i = 1, #Table do
		NewTable[ Table[ i ] ] = true
	end

	return NewTable
end

--Gets all plugins set to load their configs from the web.
local function GetWebLoadingPlugins( self )
	local WebConfig = self.Config.WebConfigs

	if not WebConfig.Enabled then
		return {}
	end

	local ActiveExtensions = self.Config.ActiveExtensions
	local PluginList = ConvertToLookup( WebConfig.Plugins )

	if WebConfig.IsBlacklist then
		local DontLoad = {}

		for Plugin, Enabled in pairs( ActiveExtensions ) do
			if not PluginList[ Plugin ] and Enabled then
				DontLoad[ Plugin ] = true
			end
		end

		return DontLoad
	end

	return PluginList
end

local function LoadPlugin( self, Name )
	if self.Plugins[ Name ] then --We already loaded it, it was a shared plugin.
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

	if self.Config.AddTag then --Would be nice to know who's running it.
		Server.AddTag( "shine" )
	end

	local AllPlugins = self.AllPlugins
	local ActiveExtensions = self.Config.ActiveExtensions
	local Modified = false

	--Find any new plugins we don't have in our config, and add them.
	for Plugin in pairs( AllPlugins ) do
		if ActiveExtensions[ Plugin ] == nil then
			local PluginTable = self.Plugins[ Plugin ]
			local DefaultState = false

			--Load, but do not enable, the extension to determine its default state.
			if not PluginTable then
				self:LoadExtension( Plugin, true )

				PluginTable = self.Plugins[ Plugin ]

				if PluginTable and PluginTable.DefaultState ~= nil then
					DefaultState = PluginTable.DefaultState
				end
			else
				if PluginTable.DefaultState ~= nil then
					DefaultState = PluginTable.DefaultState
				end
			end

			ActiveExtensions[ Plugin ] = DefaultState

			Modified = true
		end
	end

	if Modified then
		self:SaveConfig( true )
	end

	local DontEnableNow = GetWebLoadingPlugins( self )

	Notify( "Loading extensions..." )

	for Name, Enabled in pairs( ActiveExtensions ) do
		if Enabled and not DontEnableNow[ Name ] then
			LoadPlugin( self, Name )
		end
	end

	Notify( "Completed loading Shine extensions." )

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
		end, -20 )
	end
end

local function LoadDefaultConfigs( self, List )
	--Just call the default enable, it'll load the HDD/default config.
	for i = 1, #List do
		local Name = List[ i ]

		LoadPlugin( self, Name )
	end
end

local function OnFail( self, List, FailMessage, Format, ... )
	self:Print( FailMessage, Format, ... )

	Notify( "[Shine] Loading cached/default configs..." )

	LoadDefaultConfigs( self, List )

	Notify( "[Shine] Finished loading." )
end

local function OnWebPluginSuccess( self, Response, List, Reload )
	if not Response then
		OnFail( self, List, "[WebConfigs] Web request for plugin configs got a blank response. Loading default/cache files..." )

		return
	end

	local Decoded = Decode( Response )

	if not Decoded or not IsType( Decoded, "table" ) then
		OnFail( self, List, "[WebConfigs] Web request for plugin configs received invalid JSON. Loading default/cache files..." )

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

	for Name, Data in pairs( PluginData ) do
		local Success = Data.success or Data.Success
		local ConfigData = Data.config or Data.Config

		--Is the config we're loading for a specific gamemode?
		local GamemodeResponse = Data.Gamemode or Data.gamemode
		local NeedDifferentPath = GamemodeResponse and GamemodeResponse ~= DefaultGamemode

		if not Success then
			self:Print( "[WebConfigs] Server responded with error for plugin %s: %s.", true,
				Name, Data.msg or Data.Msg or "unknown error" )

			if not Reload then
				LoadPlugin( self, Name )
			end
		elseif ConfigData then
			local PluginTable = self.Plugins[ Name ]

			if PluginTable then
				--Reloading means we just need to update the given config keys.
				if Reload then
					for Key, Value in pairs( ConfigData ) do
						PluginTable.Config[ Key ] = Value
					end

					PluginTable:SaveConfig( true )
				else
					PluginTable.Config = ConfigData

					--Check and cache new/missing entries.
					if PluginTable.CheckConfig then
						Shine.CheckConfig( PluginTable.Config, PluginTable.DefaultConfig )
					end

					--Set the gamemode config path if we've been given a gamemode config.
					if NeedDifferentPath then
						PluginTable.__ConfigPath = StringFormat( "%s%s/%s",
							self.Config.ExtensionDir, GamemodeResponse, PluginTable.ConfigName )
					end

					--Cache to HDD.
					PluginTable:SaveConfig( true )

					if PluginTable.OnWebConfigLoaded then
						PluginTable:OnWebConfigLoaded()
					end

					local Success, Err = self:EnableExtension( Name, true )

					Notify( Success and StringFormat( "- Extension '%s' loaded.", Name )
						or StringFormat( "- Error loading %s: %s", Name, Err ) )
				end
			elseif not Reload then --We don't want to enable new extensions on reload.
				local Success, Err = self:LoadExtension( Name, true )

				if not Success then
					Notify( StringFormat( "- Error loading %s: %s", Name, Err ) )
				else
					PluginTable = self.Plugins[ Name ]

					PluginTable.Config = ConfigData

					if PluginTable.CheckConfig then
						Shine.CheckConfig( PluginTable.Config, PluginTable.DefaultConfig )
					end

					if NeedDifferentPath then
						PluginTable.__ConfigPath = StringFormat( "%s%s/%s",
							self.Config.ExtensionDir, GamemodeResponse, PluginTable.ConfigName )
					end

					PluginTable:SaveConfig( true )

					if PluginTable.OnWebConfigLoaded then
						PluginTable:OnWebConfigLoaded()
					end

					Success, Err = self:EnableExtension( Name, true )

					Notify( Success and StringFormat( "- Extension '%s' loaded.", Name )
						or StringFormat( "- Error loading %s: %s", Name, Err ) )
				end
			end
		else
			self:Print( "[WebConfigs] Server responded with success but supplied no config for plugin %s.", true, Name )

			if not Reload then
				LoadPlugin( self, Name )
			end
		end
	end

	if not Reload then
		Notify( "[Shine] Finished parsing web config response." )
	end
end

--Timeout means retry up to the max attempts.
local function OnWebPluginTimeout( self, Plugins, Reload )
	self.WebPluginTimeouts = ( self.WebPluginTimeouts or 0 ) + 1

	Shine:Print( "[WebConfigs] Timeout number %i on web plugin config retrieval.",
		true, self.WebPluginTimeouts )

	if self.WebPluginTimeouts >= self.Config.WebConfigs.MaxAttempts then
		if not Reload then
			Notify( "[Shine] Web config retrieval reached max retries. Loading extensions from cache/default configs..." )

			for Plugin in pairs( Plugins ) do
				LoadPlugin( self, Plugin )
			end

			Notify( "[Shine] Finished loading." )
		end

		self.WebPluginTimeouts = 0

		return
	end

	self:LoadWebPlugins( Plugins, Reload )
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

	for Plugin in pairs( Plugins ) do
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

	self.TimedHTTPRequest( WebConfig.RequestURL, "POST", Args, function( Response )
		OnWebPluginSuccess( self, Response, List, Reload )
	end, function()
		OnWebPluginTimeout( self, Plugins, Reload )
	end )
end

Shine:LoadExtensionConfigs()

if not Shine.Error then
	Shine.Hook.Call( "PostloadConfig" )
end
