--[[
	Shine permissions/user ranking system.
]]

Shine.UserData = {}

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message

local TableContains = table.contains

local UserPath = "config://shine\\UserConfig.json"

--[[
	Loads the Shine user data either from a local JSON file or from one hosted on a webserver.
	If retrieving the web users fails, it will fall back to a local file. If a local file does not exist, the default is created and used.
]]
function Shine:LoadUsers( Web )
	if Web then
		Shared.SendHTTPRequest( self.Config.UsersURL, "GET", function( Response )
			if not Response then
				self:LoadUsers()
				return
			end

			self.UserData = Decode( Response )

			Notify( "Shine loaded users from web." )
		end )

		return
	end

	local UserFile = io.open( UserPath, "r" )

	if not UserFile then
		self:GenerateDefaultUsers( true )

		return
	end

	Notify( "Loading Shine users..." )

	self.UserData = Decode( UserFile:read( "*all" ) )

	UserFile:close()
end

--[[
	Saves the Shine user data to the JSON file.
]]
function Shine:SaveUsers()
	local UserFile, Err = io.open( UserPath, "w+" )

	if not UserFile then
		Shine.Error = "Error writing user file: "..Err

		Notify( Shine.Error )

		return
	end

	UserFile:write( Encode( self.UserData, { indent = true, level = 1 } ) )

	Notify( "Saving Shine users..." )

	UserFile:close()
end

--[[
	Generates the default users and groups.
	Optionally saves the default settings to a local JSON file.
]]
function Shine:GenerateDefaultUsers( Save )
	self.UserData = {
		Groups = {
			SuperAdmin = { IsBlacklist = true, Commands = {}, Immunity = 100 },
			Admin = { IsBlacklist = false, Commands = { "sh_kick", "sh_ban" }, Immunity = 50 },
			Mod = { IsBlacklist = false, Commands = { "sh_kick" }, Immunity = 10 }
		},
		Users = {
			[ 90000000000001 ] = { Group = "Mod", Immunity = 2 }
		}
	}

	if Save then
		self:SaveUsers()
	end
end

--[[
	We need to load the users after loading the configuration file.
	This ensures we know whether we should be getting them from the web or not.
]]
Shine.Hook.Add( "PostloadConfig", "LoadShineUsers", function()
	Shine:LoadUsers( Shine.Config.GetUsersFromWeb )
end )

local function isnumber( Num )
	return type( Num ) == "number"
end

--[[
	Determines if the given client has permission to run the given command.
	Inputs: Client or Steam ID, command name (sv_*).
	Output: True if allowed.
]]
function Shine:GetPermission( Client, ConCommand )
	local Command = self.Commands[ ConCommand ]

	if not Command then return false end

	if not Client then return true end

	local ID = isnumber( Client ) and Client or Client:GetUserId()

	local User = self.UserData.Users[ tostring( ID ) ]

	if not User then
		return Command.NoPerm or false
	end

	if Command.NoPerm then return true end

	local UserGroup = User.Group
	local GroupTable = self.UserData.Groups[ UserGroup ]
	
	if not GroupTable then
		Shine:Print( "User with ID %s belongs to a non-existant group (%s)!", true, ID, UserGroup )
		return false
	end

	if GroupTable.IsBlacklist then
		return not TableContains( GroupTable.Commands, ConCommand )
	end
	
	return TableContains( GroupTable.Commands, ConCommand )
end

--[[
	Determines if the given client has raw access to the given command.
	Unlike get permission, this looks specifically for a user group with explicit permission.
	It also does not require the command to exist.
	
	Inputs: Client or Steam ID, command name (sv_*)
	Output: True if explicitly allowed.
]]
function Shine:HasAccess( Client, ConCommand )
	if not Client then return true end

	local ID = isnumber( Client ) and Client or Client:GetUserId()

	local User = self.UserData.Users[ tostring( ID ) ]

	if not User then
		return false
	end

	local UserGroup = User.Group
	local GroupTable = self.UserData.Groups[ UserGroup ]

	if not GroupTable then
		Shine:Print( "User with ID %s belongs to a non-existant group (%s)!", true, ID, UserGroup )
		return false
	end

	if GroupTable.IsBlacklist then
		return not TableContains( GroupTable.Commands, ConCommand )
	end
	
	return TableContains( GroupTable.Commands, ConCommand )
end
	

--[[
	Determines if the given client can use a command on the given target client.
	Inputs: Client (or Steam ID) calling, target client (or Steam ID).
	Output: True if allowed.
]]
function Shine:CanTarget( Client, Target )
	if not Client or not Target then return true end

	if Client == Target then return true end

	local ID = isnumber( Client ) and Client or Client:GetUserId()
	local TargetID = isnumber( Target ) and Target or Target:GetUserId()

	if ID == TargetID then return true end

	local Users = self.UserData.Users
	local Groups = self.UserData.Groups

	local User = Users[ tostring( ID ) ]
	local TargetUser = Users[ tostring( TargetID ) ]

	if not User then return false end
	if not TargetUser then return true end

	local Group = Groups[ User.Group ]
	local TargetGroup = Groups[ TargetUser.Group ]

	if not Group then
		Shine:Print( "User with ID %s belongs to a non-existant group (%s)!", true, ID, User.Group )
		return false
	end

	if not TargetGroup then
		Shine:Print( "User with ID %s belongs to a non-existant group (%s)!", true, TargetID, TargetUser.Group )
		return true 
	end

	local Immunity = User.Immunity or Group.Immunity --Read from the user's immunity first, then the groups.
	local TargetImmunity = TargetUser.Immunity or TargetGroup.Immunity

	if self.Config.EqualsCanTarget then
		return Immunity >= TargetImmunity
	end 

	return Immunity > TargetImmunity
end
