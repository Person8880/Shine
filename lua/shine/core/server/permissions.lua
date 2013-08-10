--[[
	Shine permissions/user ranking system.
]]

Shine.UserData = {}

local Encode, Decode = json.encode, json.decode
local Notify = Shared.Message

local TableContains = table.contains

local UserPath = "config://shine\\UserConfig.json"
local BackupPath = "config://Shine_UserConfig.json"
local DefaultUsers = "config://ServerAdmin.json"

function Shine:RequestUsers( Reload )
	Shared.SendHTTPRequest( self.Config.UsersURL, "GET", function( Response )
		if not Response and not Reload then
			self:LoadUsers()

			return
		end

		local UserData = Decode( Response ) or {}

		if not next( UserData ) then
			if Reload then --Don't replace with a blank table if request failed when reloading.
				self:AdminPrint( nil, "Reloading from the web failed. User data has not been changed." )

				return 
			end 

			Notify( "Loading from the web failed. Using local file instead." )

			self:LoadUsers()

			return
		end

		self.UserData = UserData

		self:ConvertData( self.UserData, true )

		--Cache the current user data, so if we fail to load it on a later map we still have something to load.
		self:SaveUsers( true )

		Notify( Reload and "Shine reloaded users from the web." or "Shine loaded users from web." )

		if Reload then
			Shine.Hook.Call( "OnUserReload" )
		end
	end )
end

--[[
	Loads the Shine user data either from a local JSON file or from one hosted on a webserver.
	If retrieving the web users fails, it will fall back to a local file. If a local file does not exist, the default is created and used.
]]
function Shine:LoadUsers( Web, Reload )
	if Web then
		if Reload then
			self:RequestUsers( true )
		else
			self.Hook.Add( "ClientConnect", "LoadUsers", function( Client )
				self:RequestUsers()
				self.Hook.Remove( "ClientConnect", "LoadUsers" )
			end, -20 )
		end

		return
	end

	--Check the default path.
	local UserFile = io.open( UserPath, "r" )

	if not UserFile then
		UserFile = io.open( BackupPath, "r" ) --Check the secondary path.

		if not UserFile then
			UserFile = io.open( DefaultUsers, "r" ) --Check the default NS2 users file.

			if not UserFile then
				self:GenerateDefaultUsers( true )

				return
			end
		end
	end

	Notify( "Loading Shine users..." )

	local Data = UserFile:read( "*all" )

	UserFile:close()

	self.UserData = Decode( Data )

	if not self.UserData or not next( self.UserData ) then
		Notify( "[Shine] The user data file is not valid JSON, unable to load user data." )
	
		Shine.Error = "The user data file is not valid JSON, unable to load user data."

		return
	end

	self:ConvertData( self.UserData )

	if Reload then
		Shine.Hook.Call( "OnUserReload" )
	end
end

local JSONSettings = {
	indent = true,
	level = 1
}

--[[
	Saves the Shine user data to the JSON file.
]]
function Shine:SaveUsers( Silent )
	local Data = Encode( self.UserData, JSONSettings )

	local UserFile, Err = io.open( UserPath, "w+" )

	if not UserFile then
		self.Error = "Error writing user file: "..Err

		Notify( self.Error )

		return
	end

	UserFile:write( Data )

	UserFile:close()

	if not Silent then
		Notify( "Saving Shine users..." )
	end
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
			[ "90000000000001" ] = { Group = "Mod", Immunity = 2 }
		}
	}

	if Save then
		self:SaveUsers()
	end
end

local function ConvertCommands( Commands )
	local Ret = {}

	for i = 1, #Commands do
		Ret[ i ] = Commands[ i ]:gsub( "sv", "sh" )	
	end

	return Ret
end

--[[
	Converts the default/DAK style user file into one compatible with Shine.
	Inputs: Userdata table, optional boolean to not save (for web loading).
]]
function Shine:ConvertData( Data, DontSave )
	local Edited
	
	if Data.groups then
		if not DontSave then
			Shared.Message( "Converting user groups from NS2/DAK format to Shine format..." )
		end
		
		Data.Groups = {}
		
		for Name, Vals in pairs( Data.groups ) do
			Data.Groups[ Name ] = { 
				IsBlacklist = Vals.type == "disallowed",
				Commands = Vals.commands and ConvertCommands( Vals.commands ) or {}, 
				Immunity = Vals.level or 10, 
				Badge = Vals.badge
			}
		end

		Edited = true
		Data.groups = nil
	end

	if Data.users then
		if not DontSave then
			Shared.Message( "Converting users from NS2/DAK format to Shine format..." )
		end

		Data.Users = {}
		
		for Name, Vals in pairs( Data.users ) do
			Data.Users[ tostring( Vals.id ) ] = { Group = Vals.groups[ 1 ], Immunity = Vals.level }
		end
		
		Edited = true
		Data.users = nil
	end

	if Edited and not DontSave then
		self:SaveUsers()
	end
end

--[[
	We need to load the users after loading the configuration file.
	This ensures we know whether we should be getting them from the web or not.
]]
Shine.Hook.Add( "PostloadConfig", "LoadShineUsers", function()
	local WebUsers = Shine.Config.GetUsersFromWeb
	Shine:LoadUsers( WebUsers )

	if WebUsers and Shine.Config.RefreshUsers then
		Shine.Timer.Create( "UserRefresh", Shine.Config.RefreshInterval or 60, -1, function()
			Shine:RequestUsers( true )
		end )
	end
end )

--[[
	Game IDs handling.
]]
local GameIDs = {}

Shine.GameIDs = GameIDs

local GameID = 0

Shine.Hook.Add( "ClientConnect", "AssignGameID", function( Client )
	GameID = GameID + 1
	GameIDs[ Client ] = GameID
end, -20 )

Shine.Hook.Add( "ClientDisconnect", "AssignGameID", function( Client ) 
	GameIDs[ Client ] = nil
end, -20 )

local function isnumber( Num )
	return type( Num ) == "number"
end

--[[
	Gets the user data table for the given client/NS2ID.
	Input: Client or NS2ID.
	Output: User data table if they are registered in UserConfig.json.
]]
function Shine:GetUserData( Client )
	if not self.UserData then return nil end
	if not self.UserData.Users then return nil end
	
	local ID = isnumber( Client ) and Client or Client:GetUserId()

	return self.UserData.Users[ tostring( ID ) ]
end

--[[
	Determines if the given client has permission to run the given command.
	Inputs: Client or Steam ID, command name (sh_*).
	Output: True if allowed.
]]
function Shine:GetPermission( Client, ConCommand )
	local Command = self.Commands[ ConCommand ]

	if not Command then return false end
	if not Client then return true end

	local User = self:GetUserData( Client )

	if not User then
		return Command.NoPerm or false
	end

	if Command.NoPerm then return true end

	local UserGroup = User.Group
	local GroupTable = self.UserData.Groups and self.UserData.Groups[ UserGroup ]
	
	if not GroupTable then
		self:Print( "User with ID %s belongs to a non-existent group (%s)!", true, ID, UserGroup )
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
	
	Inputs: Client or Steam ID, command name (sh_*)
	Output: True if explicitly allowed.
]]
function Shine:HasAccess( Client, ConCommand )
	if not Client then return true end

	local User = self:GetUserData( Client )

	if not User then
		return false
	end

	local UserGroup = User.Group
	local GroupTable = self.UserData.Groups and self.UserData.Groups[ UserGroup ]

	if not GroupTable then
		self:Print( "User with ID %s belongs to a non-existent group (%s)!", true, ID, UserGroup )
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
	if not Client or not Target then return true end --Console can target all.

	if Client == Target then return true end --Can always target yourself.

	if not self.UserData then return false end

	local ID = isnumber( Client ) and Client or Client:GetUserId()
	local TargetID = isnumber( Target ) and Target or Target:GetUserId()

	if ID == TargetID then return true end

	local Users = self.UserData.Users
	local Groups = self.UserData.Groups

	if not Users or not Groups then return false end

	local User = Users[ tostring( ID ) ]
	local TargetUser = Users[ tostring( TargetID ) ]

	if not User then return false end --No user data, guest cannot target others.
	if not TargetUser then return true end --Target is a guest, can always target guests.

	local Group = Groups[ User.Group ]
	local TargetGroup = Groups[ TargetUser.Group ]

	if not Group then
		self:Print( "User with ID %s belongs to a non-existent group (%s)!", true, ID, User.Group )
		return false
	end

	if not TargetGroup then
		self:Print( "User with ID %s belongs to a non-existent group (%s)!", true, TargetID, TargetUser.Group )
		return true 
	end

	local Immunity = User.Immunity or Group.Immunity --Read from the user's immunity first, then the groups.
	local TargetImmunity = TargetUser.Immunity or TargetGroup.Immunity

	if self.Config.EqualsCanTarget then
		return Immunity >= TargetImmunity
	end 

	return Immunity > TargetImmunity
end

--[[
	Determines if the given client is in the given user group.
	Inputs: Client (or Steam ID), group name.
	Output: Boolean result.
]]
function Shine:IsInGroup( Client, Group )
	if not Client then return false end
	if Client:GetIsVirtual() then 
		return Group:lower() == "guest" 
	end

	if not self.UserData then return false end
	
	local GroupTable = self.UserData.Groups and self.UserData.Groups[ Group ]
	if not GroupTable then return false end
	
	local UserData = self.UserData.Users

	if not UserData then return false end

	local ID = isnumber( Client ) and Client or Client:GetUserId()

	local User = UserData[ tostring( ID ) ]

	if User then
		return User.Group == Group
	end
	
	return Group:lower() == "guest"
end
