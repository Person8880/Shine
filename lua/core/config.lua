--[[
	Shine's config system.
]]

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message
local StringFormat = string.format

local ConfigPath = "config://shine\\BaseConfig.json"
local BackupPath = "config://Shine_BaseConfig.json"

function Shine:LoadConfig()
	local ConfigFile = io.open( ConfigPath, "r" )

	if not ConfigFile then
		ConfigFile = io.open( BackupPath, "r" )
		
		if not ConfigFile then
			self:GenerateDefaultConfig( true )

			return
		end
	end

	Notify( "Loading Shine config..." )

	local Config = Decode( ConfigFile:read( "*all" ) )
	self.Config = Config

	ConfigFile:close()
end

function Shine:SaveConfig()
	local ConfigFile, Err = io.open( ConfigPath, "w+" )

	if not ConfigFile then --Something's gone horribly wrong!
		Shine.Error = "Error writing config file: "..Err
		
		Notify( Shine.Error )
		
		return
	end
	
	ConfigFile:write( Encode( self.Config, { indent = true, level = 1 } ) )

	Notify( "Saving Shine config..." )
	
	ConfigFile:close()
end

function Shine:GenerateDefaultConfig( Save )
	self.Config = {
		EnableLogging = true, --Enable Shine's internal log. Note that plugins rely on this to log.
		LogDir = "config://shine\\logs\\", --Logging directory.
		DateFormat = "dd-mm-yyyy", --Format for logging dates.

		ExtensionDir = "config://shine\\plugins\\", --Plugin configs directory.

		GetUsersFromWeb = false, --Sets whether user data should be retrieved from the web.
		UsersURL = "http://www.yoursite.com/users.json", --URL to get user data from if the above is true.

		ActiveExtensions = { --Defines which plugins should be active.
			adverts = false,
			afkkick = false,
			ban = true,
			basecommands = true,
			funcommands = false,
			logging = false,
			mapvote = true,
			motd = true,
			serverswitch = false,
			unstuck = true,
			voterandom = false,
			votescramble = false,
			votesurrender = true,
			welcomemessages = false
		},

		EqualsCanTarget = false, --Defines whether users with the same immunity can target each other or not.

		ChatName = "Admin", --The default name that should appear for notifications with a name (unless in legacy mode, not all messages will show this.)

		SilentChatCommands = true, --Defines whether to silence all chat commands, or only those starting with "/".

		LegacyMode = false, --Defines whether to use Shine's customised chat system or not. This should only be used if loading from Server.lua.

		CombatMode = false --Defines whether the server's running the combat mod. This is necessary to get chat commands to work with the Combat mod.
	}

	if Save then
		self:SaveConfig()
	end
end

function Shine:LoadExtensionConfigs()
	self:LoadConfig()

	Notify( "Loading extensions..." )

	for Name, Enabled in pairs( self.Config.ActiveExtensions ) do
		if Enabled then
			local Success, Err = Shine:LoadExtension( Name )
			Notify( Success and StringFormat( "- Extension '%s' loaded.", Name ) or StringFormat( "- Error loading %s: %s", Name, Err ) )
		end
	end

	Notify( "Completed loading Shine extensions." )
end

Shine:LoadExtensionConfigs()

if not Shine.Error then
	Shine.Hook.Call( "PostloadConfig" )
end
