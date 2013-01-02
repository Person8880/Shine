--[[
	Shine's config system.
]]

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message
local StringFormat = string.format

local ConfigPath = "config://shine\\BaseConfig.json"

function Shine:LoadConfig()
	local ConfigFile = io.open( ConfigPath, "r" )

	if not ConfigFile then
		self:GenerateDefaultConfig( true )

		return
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
		ExtensionDir = "config://shine\\plugins\\", --Plugin configs directory.
		GetUsersFromWeb = false, --Sets whether user data should be retrieved from the web.
		UsersURL = "http://www.yoursite.com/users.json", --URL to get user data from if the above is true.
		DateFormat = "dd-mm-yyyy", --Format for logging dates.
		ActiveExtensions = { --Defines which plugins should be active.
			adverts = false,
			afkkick = false,
			ban = true,
			basecommands = true,
			logging = false,
			mapvote = true,
			motd = true,
			serverswitch = false,
			unstuck = true,
			votescramble = false,
			votesurrender = true,
			welcomemessages = false
		},
		EqualsCanTarget = false, --Defines whether users with the same immunity can target each other or not.
		SilentChatCommands = true, --Defines whether to silence all chat commands, or only those starting with "/".
		LegacyMode = false --Defines whether to use Shine's customised chat system or not. This should only be used if loading from Server.lua.
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
