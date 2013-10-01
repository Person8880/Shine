--[[
	Shine's config system.
]]

local Notify = Shared.Message
local pairs = pairs
local StringFormat = string.format

local ConfigPath = "config://shine/BaseConfig.json"
local BackupPath = "config://Shine_BaseConfig.json"

local DefaultConfig = {
	EnableLogging = true, --Enable Shine's internal log. Note that plugins rely on this to log.
	LogDir = "config://shine/logs/", --Logging directory.
	DateFormat = "dd-mm-yyyy", --Format for logging dates.
	TimeOffset = 0, --Offset from GMT/UTC.

	ExtensionDir = "config://shine/plugins/", --Plugin configs directory.

	GetUsersFromWeb = false, --Sets whether user data should be retrieved from the web.
	UsersURL = "http://www.yoursite.com/users.json", --URL to get user data from if the above is true.
	RefreshUsers = false, --Auto-refresh users every set amount of time.
	RefreshInterval = 60, --How long in seconds between refreshes?

	ActiveExtensions = { --Defines which plugins should be active.
		adverts = false,
		afkkick = false,
		badges = false,
		ban = true,
		basecommands = true,
		funcommands = false,
		logging = false,
		mapvote = true,
		motd = true,
		namefilter = false,
		pingtracker = false,
		pregame = false,
		readyroom = false,
		reservedslots = false,
		serverswitch = false,
		tournamentmode = false,
		unstuck = true,
		voterandom = false,
		votesurrender = true,
		welcomemessages = false,
		workshopupdater = false
	},

	EqualsCanTarget = false, --Defines whether users with the same immunity can target each other or not.

	ChatName = "Admin", --The default name that should appear for notifications with a name (not all messages will show this.)

	SilentChatCommands = true, --Defines whether to silence all chat commands, or only those starting with "/".

	AddTag = true, --Add 'shine' as a server tag.

	ReportErrors = true --Should errors be reported at the end of a round?
}

local CheckConfig = Shine.RecursiveCheckConfig

function Shine:LoadConfig()
	local ConfigFile = self.LoadJSONFile( ConfigPath )

	if not ConfigFile then
		ConfigFile = self.LoadJSONFile( BackupPath )
		
		if not ConfigFile then
			self:GenerateDefaultConfig( true )

			return
		end
	end

	Notify( "Loading Shine config..." )

	self.Config = ConfigFile

	if CheckConfig( self.Config, DefaultConfig, true ) then
		self:SaveConfig()
	end
end

function Shine:SaveConfig( Silent )
	local ConfigFile, Err = self.SaveJSONFile( self.Config, ConfigPath )

	if not ConfigFile then --Something's gone horribly wrong!
		Shine.Error = "Error writing config file: "..Err
		
		Notify( Shine.Error )
		
		return
	end

	if not Silent then
		Notify( "Updating Shine config..." )
	end
end

function Shine:GenerateDefaultConfig( Save )
	self.Config = DefaultConfig

	if Save then
		self:SaveConfig()
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

	Notify( "Loading extensions..." )

	for Name, Enabled in pairs( ActiveExtensions ) do
		if Enabled then
			if self.Plugins[ Name ] then --We already loaded it, it was a shared plugin.
				local Success, Err = self:EnableExtension( Name )
				Notify( Success and StringFormat( "- Extension '%s' loaded.", Name ) or StringFormat( "- Error loading %s: %s.", Name, Err ) )
			else
				local Success, Err = self:LoadExtension( Name )
				Notify( Success and StringFormat( "- Extension '%s' loaded.", Name ) or StringFormat( "- Error loading %s: %s.", Name, Err ) )
			end
		end
	end

	Notify( "Completed loading Shine extensions." )
end

Shine:LoadExtensionConfigs()

if not Shine.Error then
	Shine.Hook.Call( "PostloadConfig" )
end
