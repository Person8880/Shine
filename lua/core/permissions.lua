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

--[[
	Loads the Shine user data either from a local JSON file or from one hosted on a webserver.
	If retrieving the web users fails, it will fall back to a local file. If a local file does not exist, the default is created and used.
]]
function Shine:LoadUsers( Web )
	if Web then
		Shine.Hook.Add( "ClientConnect", "LoadUsers", function( Client )
			Shared.SendHTTPRequest( self.Config.UsersURL, "GET", function( Response )
				if not Response then
					self:LoadUsers()
					return
				end

				self.UserData = Decode( Response ) or {}

				if not next( self.UserData ) then
					self:LoadUsers()
					return
				end

				self:ConvertData( self.UserData, true )

				Notify( "Shine loaded users from web." )
			end )
		end, -20 )

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

	self.UserData = Decode( UserFile:read( "*all" ) )

	UserFile:close()

	self:ConvertData( self.UserData )
end

--[[
	Saves the Shine user data to the JSON file.
]]
function Shine:SaveUsers()
	local UserFile, Err = io.open( UserPath, "w+" )

	if not UserFile then
		self.Error = "Error writing user file: "..Err

		Notify( self.Error )

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
		Shared.Message( "Converting user groups from NS2/DAK format to Shine format..." )
		
		Data.Groups = {}
		
		for Name, Vals in pairs( Data.groups ) do
			Data.Groups[ Name ] = { IsBlacklist = Vals.type == "disallowed", Commands = ConvertCommands( Vals.commands ), Immunity = Vals.level or 10 }
		end
		Edited = true
		Data.groups = nil
	end

	if Data.users then
		Shared.Message( "Converting users from NS2/DAK format to Shine format..." )

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
	Shine:LoadUsers( Shine.Config.GetUsersFromWeb )
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
end )

Shine.Hook.Add( "ClientDisconnect", "AssignGameID", function( Client ) 
	GameIDs[ Client ] = nil
end )

local function isnumber( Num )
	return type( Num ) == "number"
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

	if not self.UserData then return false end
	if not self.UserData.Users then return false end

	local ID = isnumber( Client ) and Client or Client:GetUserId()

	local User = self.UserData.Users[ tostring( ID ) ]

	if not User then
		return Command.NoPerm or false
	end

	if Command.NoPerm then return true end

	local UserGroup = User.Group
	local GroupTable = self.UserData.Groups and self.UserData.Groups[ UserGroup ]
	
	if not GroupTable then
		self:Print( "User with ID %s belongs to a non-existant group (%s)!", true, ID, UserGroup )
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

	if not self.UserData then return false end
	if not self.UserData.Users then return false end

	local ID = isnumber( Client ) and Client or Client:GetUserId()

	local User = self.UserData.Users[ tostring( ID ) ]

	if not User then
		return false
	end

	local UserGroup = User.Group
	local GroupTable = self.UserData.Groups and self.UserData.Groups[ UserGroup ]

	if not GroupTable then
		self:Print( "User with ID %s belongs to a non-existant group (%s)!", true, ID, UserGroup )
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
		self:Print( "User with ID %s belongs to a non-existant group (%s)!", true, ID, User.Group )
		return false
	end

	if not TargetGroup then
		self:Print( "User with ID %s belongs to a non-existant group (%s)!", true, TargetID, TargetUser.Group )
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
	if Client:GetIsVirtual() then return false end

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
